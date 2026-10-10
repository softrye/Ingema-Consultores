package com.ingema.ingeplus;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.database.Cursor;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.OpenableColumns;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.webkit.ConsoleMessage;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.biometric.BiometricManager;
import androidx.webkit.WebViewAssetLoader;

import org.qtproject.qt.android.bindings.QtActivity;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.json.JSONObject;

/**
 * Qt owns the Activity (minimal root window, Visual Zero 2026-10-10). No
 * Flutter surface is hosted here; the Cesium engine (Earth) is created only
 * on demand and its document/location/export services stay in this class.
 */
public final class InGeQtActivity extends QtActivity {
    private static final String EARTH_ASSET_URL =
            "https://appassets.androidplatform.net/assets/cesium/index.html";
    private static final int LOCATION_PERMISSION_REQUEST = 8104;
    private static final int EARTH_IMPORT_REQUEST = 8105;
    private static final int EARTH_EXPORT_REQUEST = 8106;
    private static final int BIOMETRIC_AUTH_REQUEST = 8107;
    private static final int RENDITION_ATTACHMENT_REQUEST = 8108;
    private static final long LOCATION_TIMEBOX_MS = 8_000L;
    // A GNSS cold start without assistance needs 18-30 s of continuous
    // tracking. While the best fix is coarse the chip keeps tracking up to
    // this bound from the start of the search, then it is always released.
    private static final long LOCATION_SESSION_MAX_MS = 90_000L;
    private static final double LOCATION_PRECISE_M = 20.0;

    private static WeakReference<InGeQtActivity> current = new WeakReference<>(null);

    private java.util.function.Consumer<Boolean> pendingBiometricResult;
    private java.util.function.Consumer<Map<String, Object>> pendingRenditionAttachmentResult;
    private final ExecutorService renditionAttachmentExecutor =
            Executors.newSingleThreadExecutor();

    private WebView earthWebView;
    private WebViewAssetLoader earthAssetLoader;
    private boolean earthWebViewLoaded;
    private long earthRendererLostAtMs;
    // LOW/ULTRA_LOW: a hidden Cesium WebView is released shortly after it
    // leaves the screen; other tiers keep it for a fast reopen and release it
    // only when Android reports memory pressure (onTrimMemory).
    private static final long EARTH_LOW_TIER_RELEASE_MS = 2_000L;
    private final Runnable releaseHiddenEarthRunnable =
            () -> releaseHiddenEarthWebView("low_tier_hidden");
    private boolean activityResumed;
    private Configuration lastConfiguration;
    private float preferredRefreshRateHz;
    private InGePerformanceRuntime performanceRuntime;
    private final Handler performanceHandler = new Handler(Looper.getMainLooper());

    private final Handler locationHandler = new Handler(Looper.getMainLooper());
    private final Map<String, Object> bestLocationFix = new HashMap<>();
    private long locationSearchStartedMs;
    private long locationLastImprovedMs;
    private long locationLastObservedTimestamp;
    private double locationBestScore = Double.POSITIVE_INFINITY;
    private long locationRefineUntilMs;
    private boolean pendingEarthWebImport;
    private boolean pendingEarthWebExport;
    private File pendingEarthWebExportFile;
    private OutputStream pendingEarthWebExportStream;
    private String pendingEarthWebExportName;
    private String pendingEarthWebExportMime;

    private static native void nativeRecordBetaDiagnostic(String eventJson);

    private final Runnable locationPoll = this::pollEarthLocation;
    private final Runnable locationRefinePoll =
            this::pollEarthLocationRefinement;
    private final Runnable betaPerformanceSample = new Runnable() {
        @Override
        public void run() {
            emitBetaPerformanceSample();
            if (activityResumed)
                performanceHandler.postDelayed(this, 15_000L);
        }
    };
    private boolean betaCrashHandlerInstalled;

    public static InGeQtActivity currentActivity() {
        return current.get();
    }

    public static String betaDeviceSnapshotJson() {
        final InGeQtActivity activity = current.get();
        return activity == null ? "{}" : activity.buildBetaDeviceSnapshot().toString();
    }

    private static void emitBetaDiagnostic(String category, String severity,
                                           String code, String message,
                                           JSONObject metrics,
                                           JSONObject context) {
        try {
            final JSONObject event = new JSONObject();
            event.put("category", category == null ? "ANDROID" : category);
            event.put("severity", severity == null ? "INFO" : severity);
            event.put("code", code == null ? "ANDROID_EVENT" : code);
            if (message != null && !message.isEmpty()) event.put("message", message);
            event.put("metrics", metrics == null ? new JSONObject() : metrics);
            event.put("context", context == null ? new JSONObject() : context);
            nativeRecordBetaDiagnostic(event.toString());
        } catch (Throwable ignored) {
            // Telemetry is strictly best effort and must never affect the app.
        }
    }

    private JSONObject buildBetaDeviceSnapshot() {
        final JSONObject device = new JSONObject();
        try {
            final DisplayMetrics display = getResources().getDisplayMetrics();
            device.put("manufacturer", Build.MANUFACTURER);
            device.put("model", Build.MODEL);
            device.put("android_version", Build.VERSION.RELEASE);
            device.put("sdk_version", Build.VERSION.SDK_INT);
            device.put("screen_width_px", display.widthPixels);
            device.put("screen_height_px", display.heightPixels);
            device.put("screen_width_logical", display.widthPixels / display.density);
            device.put("screen_height_logical", display.heightPixels / display.density);
            device.put("device_pixel_ratio", display.density);
            device.put("density_dpi", display.densityDpi);
            final android.content.pm.PackageInfo packageInfo =
                    getPackageManager().getPackageInfo(getPackageName(), 0);
            device.put("app_version", packageInfo.versionName == null
                    ? "" : packageInfo.versionName);
            device.put("app_build", Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    ? Long.toString(packageInfo.getLongVersionCode())
                    : Integer.toString(packageInfo.versionCode));

            final InGePerformanceRuntime runtime = performanceRuntime != null
                    ? performanceRuntime : InGePerformanceRuntime.get();
            if (runtime != null) {
                final InGePerformanceRuntime.Capabilities capabilities =
                        runtime.capabilities();
                device.put("ram_bytes", capabilities.totalMemoryBytes);
                device.put("memory_class_mb", capabilities.memoryClassMb);
                device.put("low_ram_device", capabilities.lowRamDevice);
                device.put("cpu_logical_cores", capabilities.logicalCores);
                device.put("display_refresh_hz", capabilities.currentRefreshHz);
                device.put("performance_tier", runtime.deviceTier().name());
                device.put("flutter_renderer", capabilities.flutterRenderer);
                device.put("gles_version_hex", "0x" + Integer.toHexString(
                        capabilities.requiredOpenGlEsVersion));
                device.put("hardware_vulkan_supported", capabilities.vulkanSupported);
                device.put("qt_backend_source", "GraphicsCore.graphicsBackend");
            }
        } catch (Throwable ignored) {
            // A partial technical snapshot is still useful and privacy safe.
        }
        return device;
    }

    private void emitBetaPerformanceSample() {
        if (performanceRuntime == null) return;
        try {
            final InGePerformanceRuntime.FrameSnapshot snapshot =
                    performanceRuntime.snapshot();
            final JSONObject metrics = new JSONObject();
            metrics.put("frame_interval_avg_ms", snapshot.averageFrameTimeMs);
            metrics.put("frame_interval_p95_ms", snapshot.p95FrameTimeMs);
            metrics.put("estimated_fps", snapshot.averageFrameTimeMs > 0.0
                    ? 1000.0 / snapshot.averageFrameTimeMs : 0.0);
            metrics.put("jank_count_window", snapshot.recentJankCount);
            metrics.put("frame_count_window", snapshot.recentFrameCount);
            final JSONObject context = new JSONObject();
            context.put("active_subapp", snapshot.state.name().toLowerCase(Locale.ROOT));
            emitBetaDiagnostic("PERFORMANCE", "INFO", "FRAME_WINDOW_SAMPLE",
                    null, metrics, context);
        } catch (Throwable ignored) {
        }
    }

    private void installBetaCrashHandler() {
        if (betaCrashHandlerInstalled) return;
        betaCrashHandlerInstalled = true;
        final Thread.UncaughtExceptionHandler previous =
                Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            final JSONObject context = new JSONObject();
            try {
                context.put("exception_type", error == null
                        ? "Throwable" : error.getClass().getName());
                if (thread != null) context.put("thread", thread.getName());
                if (error != null) {
                    final StringBuilder summary = new StringBuilder();
                    final StackTraceElement[] stack = error.getStackTrace();
                    for (int index = 0; index < Math.min(8, stack.length); ++index) {
                        if (index > 0) summary.append(" | ");
                        summary.append(stack[index].toString());
                    }
                    context.put("stack_summary", summary.toString());
                }
            } catch (Throwable ignored) {
            }
            emitBetaDiagnostic("ERROR", "FATAL", "ANDROID_UNCAUGHT_EXCEPTION",
                    null, null, context);
            if (previous != null) previous.uncaughtException(thread, error);
        });
    }

    // P0 gray startup. Qt 6.9 (QtActivityBase/QtActivityDelegate) loads the Qt
    // libraries through a process-wide QtActivityLoader singleton and defers
    // QtNative.startApplication() to the first global layout of the Activity.
    // When Android relaunches the Activity before that layout pass (e.g.
    // ActivityThread "Relaunch all activities: onCoreSettingsChange", which no
    // configChanges entry can prevent), main() never ran (isStarted=false), the
    // retained onDestroy keeps the process, and the new Activity gets
    // LoadingResult.AlreadyLoaded from the stale loader: Qt's onCreate then
    // starts nothing and only the window background is drawn.
    // Only in that exact state (libraries loaded, Qt never started) the stale
    // loader, still bound to the destroyed Activity, is discarded so Qt rebuilds
    // it for this Activity and runs its normal deferred start. A started Qt, a
    // cold start and a normal Activity are never touched: no double start.
    private static void recoverQtStartIfNeverRan() {
        try {
            final Class<?> nativeClass = Class.forName("org.qtproject.qt.android.QtNative");
            final java.lang.reflect.Method stateMethod = nativeClass.getDeclaredMethod("getStateDetails");
            stateMethod.setAccessible(true);
            final Object details = stateMethod.invoke(null);
            final java.lang.reflect.Field startedField = details.getClass().getDeclaredField("isStarted");
            startedField.setAccessible(true);
            final boolean started = startedField.getBoolean(details);
            java.lang.reflect.Field instanceField = null;
            for (Class<?> c = Class.forName("org.qtproject.qt.android.QtActivityLoader");
                 c != null && instanceField == null; c = c.getSuperclass()) {
                try { instanceField = c.getDeclaredField("m_instance"); } catch (NoSuchFieldException ignored) {}
            }
            if (instanceField == null) {
                android.util.Log.w("InGeLifecycle", "INGE_QT_PROCESS_STATE started=" + started + " loader=unknown");
                return;
            }
            instanceField.setAccessible(true);
            final Object loader = instanceField.get(null);
            boolean librariesLoaded = false;
            if (loader != null) {
                for (Class<?> c = loader.getClass(); c != null; c = c.getSuperclass()) {
                    try {
                        final java.lang.reflect.Field loaded = c.getDeclaredField("m_librariesLoaded");
                        loaded.setAccessible(true);
                        librariesLoaded = loaded.getBoolean(loader);
                        break;
                    } catch (NoSuchFieldException ignored) {}
                }
            }
            android.util.Log.i("InGeLifecycle", "INGE_QT_PROCESS_STATE started=" + started
                    + " loader=" + (loader != null) + " librariesLoaded=" + librariesLoaded);
            if (started || loader == null || !librariesLoaded)
                return;   // cold start, or Qt already running (Qt's own path applies)
            instanceField.set(null, null);
            android.util.Log.i("InGeLifecycle", "INGE_STARTUP_REENTRY reason=qt_never_started_before_recreation");
        } catch (Throwable error) {
            android.util.Log.w("InGeLifecycle", "INGE_STARTUP_REENTRY_UNAVAILABLE " + error);
        }
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_CREATE instance=" + System.identityHashCode(this)
                + " recreated=" + (savedInstanceState != null));
        android.util.Log.i("InGeLifecycle", "INGE_STARTUP_EARTH_TIER_READ=NO");
        current = new WeakReference<>(this);
        recoverQtStartIfNeverRan();
        super.onCreate(savedInstanceState);
        lastConfiguration = new Configuration(getResources().getConfiguration());
        performanceRuntime = InGePerformanceRuntime.initialize(getWindow());
        installBetaCrashHandler();
        emitBetaDiagnostic("DEVICE", "INFO", "DEVICE_SNAPSHOT", null, null,
                buildBetaDeviceSnapshot());
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_CREATE", null, null, null);
        configureAdaptiveRefreshRate();
        // Battery saver / thermal changes move the live tier: re-apply the
        // refresh cap and publish the state to Qt (GraphicsCore).
        performanceRuntime.setBudgetListener(this::configureAdaptiveRefreshRate);
        performanceRuntime.startMonitoring();
    }

    @Override
    protected void onResume() {
        super.onResume();
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_RESUME instance=" + System.identityHashCode(this));
        activityResumed = true;
        if (performanceRuntime != null)
            performanceRuntime.onTrimMemory(0);
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_RESUME", null, null, null);
        performanceHandler.removeCallbacks(betaPerformanceSample);
        performanceHandler.postDelayed(betaPerformanceSample, 15_000L);
        if (performanceRuntime != null)
            performanceRuntime.setTrackingEnabled(true);
        if (earthWebView != null)
            earthWebView.onResume();
    }

    @Override
    protected void onPause() {
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_PAUSE instance=" + System.identityHashCode(this));
        activityResumed = false;
        emitBetaPerformanceSample();
        performanceHandler.removeCallbacks(betaPerformanceSample);
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_PAUSE", null, null, null);
        if (performanceRuntime != null)
            performanceRuntime.setTrackingEnabled(false);
        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_ON_PAUSE_BEGIN");

        // P0: Qt debe recibir el pause inmediatamente, antes que el WebView,
        // para no presentar un frame mientras Android retira la Surface.
        super.onPause();

        if (earthWebView != null) {
            stopEarthLocationSearch();
            earthWebView.onPause();
        }

        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_ON_PAUSE_END");
    }

    @Override
    protected void onStop() {
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_STOP", null, null, null);
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_STOP instance=" + System.identityHashCode(this));
        super.onStop();
    }

    // Android 14+ only delivers TRIM_MEMORY_UI_HIDDEN and _BACKGROUND; older
    // versions also RUNNING_LOW/CRITICAL while in the foreground.
    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        android.util.Log.i("InGePerformance", "INGE_TRIM_MEMORY level=" + level
                + " earthAlive=" + (earthWebView != null));
        if (performanceRuntime != null)
            performanceRuntime.onTrimMemory(level);
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
            releaseHiddenEarthWebView("trim_" + level);
    }

    @Override
    public void onLowMemory() {
        super.onLowMemory();
        onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE);
    }

    @Override
    public void onConfigurationChanged(@NonNull Configuration newConfig) {
        final Configuration previous = lastConfiguration == null
                ? null : new Configuration(lastConfiguration);
        final int diff = previous == null ? 0 : previous.diff(newConfig);
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_CONFIG_CHANGE=" + diff
                        + " instance=" + System.identityHashCode(this));
        lastConfiguration = new Configuration(newConfig);
        super.onConfigurationChanged(newConfig);
        if (performanceRuntime != null)
            performanceRuntime.updateFontScale(newConfig.fontScale);
    }

    // Capability-derived request: never clamp every device to one global rate.
    // The budget already picks a physical panel rate for the device tier. When
    // it reaches the panel's top rate there is no request at all, so the system
    // (adaptive/LTPO, the user's smooth-display setting) keeps deciding; when it
    // is lower (LOW tier on a 90/120 Hz panel) the window is capped to it. The
    // rate read at onCreate is not used: it pinned flagships idling at 60 Hz.
    // preferredRefreshRate (not a mode id): the system maps it to a mode of the
    // default resolution of whichever display hosts the window, so folding or
    // moving to another display keeps the cap without recomputing ids.
    private void configureAdaptiveRefreshRate() {
        try {
            float requestHz = 0.0f;
            if (performanceRuntime != null) {
                final float[] supported =
                        performanceRuntime.capabilities().supportedRefreshRates;
                final float panelMaxHz = supported.length == 0
                        ? 0.0f : supported[supported.length - 1];
                final float budgetHz =
                        performanceRuntime.budget().sustainableRefreshHz;
                if (panelMaxHz > 0.0f && budgetHz + 0.5f < panelMaxHz)
                    requestHz = budgetHz;
            }
            preferredRefreshRateHz = requestHz;
            final android.view.WindowManager.LayoutParams params =
                    getWindow().getAttributes();
            params.preferredRefreshRate = requestHz;
            getWindow().setAttributes(params);

            android.util.Log.i("InGePerformance",
                    "INGE_REFRESH_REQUEST_HZ=" + requestHz
                            + (requestHz > 0.0f ? "" : " owner=system"));

            getWindow().getDecorView().post(
                    () -> applyPreferredFrameRateToSurfaces(
                            getWindow().getDecorView()));
        } catch (Throwable error) {
            android.util.Log.w("InGePerformance",
                    "INGE_REFRESH_REQUEST_FAILED", error);
        }
    }

    private void applyPreferredFrameRateToSurfaces(View view) {
        if (view == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.R)
            return;

        if (view instanceof android.view.SurfaceView) {
            try {
                final android.view.Surface surface =
                        ((android.view.SurfaceView) view).getHolder().getSurface();
                if (surface != null && surface.isValid()) {
                    surface.setFrameRate(
                            preferredRefreshRateHz,
                            android.view.Surface.FRAME_RATE_COMPATIBILITY_DEFAULT);
                }
            } catch (Throwable error) {
                android.util.Log.w("InGePerformance",
                        "INGE_SURFACE_FRAME_RATE_FAILED", error);
            }
        }

        if (view instanceof ViewGroup) {
            final ViewGroup group = (ViewGroup) view;
            for (int index = 0; index < group.getChildCount(); ++index)
                applyPreferredFrameRateToSurfaces(group.getChildAt(index));
        }
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            getWindow().getDecorView().post(
                    () -> applyPreferredFrameRateToSurfaces(
                            getWindow().getDecorView()));
            try {
                final android.view.Display activeDisplay =
                        getWindowManager().getDefaultDisplay();
                if (activeDisplay != null) {
                    android.util.Log.i("InGePerformance",
                            "INGE_DISPLAY_ACTIVE_HZ=" + activeDisplay.getRefreshRate());
                }
            } catch (Throwable ignored) {}
        }
    }

    @SuppressLint({"SetJavaScriptEnabled", "JavascriptInterface"})
    private void ensureDirectEarthWebView() {
        if (earthWebView != null)
            return;

        // Each WebView keeps its own loader: requests already queued by a
        // WebView whose renderer died may still arrive after the field is reset.
        final WebViewAssetLoader assetLoader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/",
                        new WebViewAssetLoader.AssetsPathHandler(this))
                .build();
        earthAssetLoader = assetLoader;

        final WebView webView = new WebView(this);
        final WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(false);
        // Android nativo es el único propietario de permisos/GPS para Earth.
        settings.setGeolocationEnabled(false);

        // Mismo tono que la pantalla de carga de Earth: sin flash negro.
        webView.setBackgroundColor(Color.rgb(7, 17, 28));
        webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        webView.setVisibility(View.GONE);
        webView.addJavascriptInterface(
                new EarthTelemetryBridge(), "InGeEarthTelemetry");
        webView.addJavascriptInterface(
                new EarthConfigBridge(), "InGeEarthConfig");
        webView.addJavascriptInterface(
                new EarthUiBridge(), "InGeEarthUiBridge");
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(
                    WebView view, WebResourceRequest request) {
                return assetLoader.shouldInterceptRequest(request.getUrl());
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                earthWebViewLoaded = true;
                android.util.Log.i("InGeEarthDirect",
                        "INGE_EARTH_DIRECT_PAGE_LOADED url=" + url);
            }

            @Override
            public boolean onRenderProcessGone(WebView view,
                                               RenderProcessGoneDetail detail) {
                // Unhandled, Android 8+ kills the whole app with the renderer.
                recoverEarthRendererGone(view,
                        detail != null && detail.didCrash());
                return true;
            }
        });
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onConsoleMessage(ConsoleMessage message) {
                android.util.Log.i("InGeEarthDirectJS", message.message());
                return true;
            }
        });

        final FrameLayout content = findViewById(android.R.id.content);
        final FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.TOP | Gravity.START);
        content.addView(webView, params);
        earthWebView = webView;
        webView.loadUrl(EARTH_ASSET_URL);
        android.util.Log.i("InGeEarthDirect",
                "INGE_EARTH_DIRECT_WEBVIEW_CREATED hardware=true assetLoader=androidx.webkit");
    }

    private boolean isLowMemoryTier() {
        final InGePerformanceRuntime runtime = performanceRuntime;
        if (runtime == null)
            return false;
        final InGePerformanceRuntime.DeviceTier tier = runtime.baseTier();
        return tier == InGePerformanceRuntime.DeviceTier.LOW
                || tier == InGePerformanceRuntime.DeviceTier.ULTRA_LOW
                || runtime.capabilities().lowRamDevice;
    }

    // Frees the Cesium WebGL context, tiles and its renderer while it is not
    // shown; the next ensureDirectEarthWebView() recreates it.
    private void releaseHiddenEarthWebView(String reason) {
        if (earthWebView == null)
            return;
        if (earthWebView.getVisibility() == View.VISIBLE && earthWebView.isEnabled())
            return;
        android.util.Log.i("InGeEarthDirect",
                "INGE_EARTH_WEBVIEW_RELEASED reason=" + reason);
        destroyDirectEarthWebView();
    }









    private void destroyDirectEarthWebView() {
        final WebView webView = earthWebView;
        earthWebView = null;
        earthAssetLoader = null;
        earthWebViewLoaded = false;
        if (webView == null)
            return;
        try { webView.removeJavascriptInterface("InGeEarthTelemetry"); }
        catch (Throwable ignored) {}
        try { webView.removeJavascriptInterface("InGeEarthConfig"); }
        catch (Throwable ignored) {}
        try { webView.removeJavascriptInterface("InGeEarthUiBridge"); }
        catch (Throwable ignored) {}
        try { webView.stopLoading(); } catch (Throwable ignored) {}
        final ViewParent parent = webView.getParent();
        if (parent instanceof ViewGroup)
            ((ViewGroup) parent).removeView(webView);
        try { webView.destroy(); } catch (Throwable ignored) {}
    }

    // Android (or the OEM) kills a hidden Cesium renderer to reclaim memory; a
    // dead WebView is unusable: it is released and recreated on next demand.
    private void recoverEarthRendererGone(WebView view, boolean crashed) {
        final boolean current = view == earthWebView;
        final boolean wasVisible = current && activityResumed
                && view.getVisibility() == View.VISIBLE;
        final long nowElapsed = SystemClock.elapsedRealtime();
        final boolean repeated = wasVisible && earthRendererLostAtMs > 0L
                && nowElapsed - earthRendererLostAtMs < 30_000L;
        if (wasVisible)
            earthRendererLostAtMs = nowElapsed;
        android.util.Log.e("InGeEarthDirect",
                "INGE_EARTH_RENDERER_GONE crashed=" + crashed
                        + " current=" + current + " visible=" + wasVisible
                        + " foreground=" + activityResumed
                        + " repeated=" + repeated);
        final JSONObject context = new JSONObject();
        try {
            context.put("current", current);
            context.put("visible", wasVisible);
            context.put("foreground", activityResumed);
            context.put("repeated", repeated);
        } catch (org.json.JSONException ignored) {}
        reportWebViewRendererGone("EARTH", crashed, context);
        if (!current) {
            final ViewParent parent = view.getParent();
            if (parent instanceof ViewGroup)
                ((ViewGroup) parent).removeView(view);
            try { view.destroy(); } catch (Throwable ignored) {}
            return;
        }
        stopEarthLocationSearch();
        destroyDirectEarthWebView();
    }

    // Renderer loss is recovered silently for the user, never for diagnostics
    // (AGENTS.md rule 2). didCrash=true is a real renderer/GPU crash.
    static void reportWebViewRendererGone(String surface, boolean crashed,
                                          JSONObject context) {
        emitBetaDiagnostic("ERROR", crashed ? "ERROR" : "WARNING",
                surface + "_RENDERER_GONE", null, null, context);
    }

    private final class EarthTelemetryBridge {
        @JavascriptInterface
        public void post(String event) {
            if (event == null || !event.startsWith("INGE_EARTH_"))
                return;
            android.util.Log.i("InGeEarthDirect", event);
        }
    }

    private static final class EarthConfigBridge {
        @JavascriptInterface
        public String getCesiumIonToken() {
            final String token = BuildConfig.CESIUM_ION_TOKEN;
            return token == null ? "" : token.trim();
        }

        @JavascriptInterface
        public String getGoogleMapsApiKey() {
            final String key = BuildConfig.GOOGLE_MAPS_API_KEY;
            return key == null ? "" : key.trim();
        }

        @JavascriptInterface
        public String getDefaultMapUrl() {
            final String url = BuildConfig.DEFAULT_MAP_URL;
            return url == null ? "" : url.trim();
        }

        @JavascriptInterface
        public String getTerrainUrl() {
            final String url = BuildConfig.TERRAIN_URL;
            return url == null ? "" : url.trim();
        }

        @JavascriptInterface
        public String getValhallaBaseUrl() {
            final String url = BuildConfig.VALHALLA_BASE_URL;
            return url == null ? "" : url.trim();
        }

        @JavascriptInterface
        public String getEarthPerformanceTier() {
            android.util.Log.i("InGeLifecycle", "INGE_STARTUP_EARTH_TIER_READ=YES");
            final InGePerformanceRuntime runtime = InGePerformanceRuntime.get();
            if (runtime == null)
                return "MID";
            switch (runtime.deviceTier()) {
                case ULTRA_LOW:
                case LOW:
                    return "LOW";
                case HIGH:
                    return "HIGH";
                case MEDIUM:
                case MEDIUM_HIGH:
                default:
                    return "MID";
            }
        }
    }

    private final class EarthUiBridge {

        @JavascriptInterface
        public void requestLocation() {
            runOnUiThread(() -> startEarthLocationSearch());
        }

        @JavascriptInterface
        public void openEarthDocument() {
            runOnUiThread(() -> startEarthWebDocumentPicker());
        }

        @JavascriptInterface
        public synchronized void beginEarthExport(
                String name, String mime, int expectedChunks) {
            closePendingEarthWebExport();
            if (expectedChunks < 0)
                return;
            try {
                pendingEarthWebExportName = sanitizeEarthExportName(name);
                pendingEarthWebExportMime = mime != null && mime.contains("kmz")
                        ? "application/vnd.google-earth.kmz"
                        : "application/vnd.google-earth.kml+xml";
                pendingEarthWebExportFile = File.createTempFile(
                        "inge-earth-export-", ".tmp", getCacheDir());
                pendingEarthWebExportStream =
                        new FileOutputStream(pendingEarthWebExportFile);
            } catch (Throwable error) {
                closePendingEarthWebExport();
                emitEarthExportResult(false, "No se pudo preparar la exportación");
            }
        }

        @JavascriptInterface
        public synchronized void appendEarthExportChunk(String base64Chunk) {
            if (pendingEarthWebExportStream == null || base64Chunk == null)
                return;
            try {
                final byte[] bytes = android.util.Base64.decode(
                        base64Chunk, android.util.Base64.DEFAULT);
                pendingEarthWebExportStream.write(bytes);
            } catch (Throwable error) {
                closePendingEarthWebExport();
                emitEarthExportResult(false, "No se pudo recibir la exportación");
            }
        }

        @JavascriptInterface
        public synchronized void finishEarthExport() {
            if (pendingEarthWebExportStream == null
                    || pendingEarthWebExportFile == null)
                return;
            try {
                pendingEarthWebExportStream.flush();
                pendingEarthWebExportStream.close();
                pendingEarthWebExportStream = null;
                runOnUiThread(() -> startEarthWebExportPicker());
            } catch (Throwable error) {
                closePendingEarthWebExport();
                emitEarthExportResult(false, "No se pudo completar la exportación");
            }
        }
    }

    private boolean isBiometricAvailable() {
        try {
            final BiometricManager manager = BiometricManager.from(this);
            return manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
                    == BiometricManager.BIOMETRIC_SUCCESS;
        } catch (Throwable ignored) {
            return false;
        }
    }

    // Verificación biométrica del sistema (BiometricPrompt en
    // InGeBiometricActivity). Sin consumidor visual tras Visual Zero.
    private void authenticateBiometric(java.util.function.Consumer<Boolean> result) {
        if (!isBiometricAvailable() || pendingBiometricResult != null) {
            result.accept(false);
            return;
        }
        pendingBiometricResult = result;
        try {
            startActivityForResult(
                    new Intent(this, InGeBiometricActivity.class),
                    BIOMETRIC_AUTH_REQUEST);
        } catch (Throwable error) {
            pendingBiometricResult = null;
            result.accept(false);
        }
    }

    // Selector de sustentos de Rendiciones: copia a almacenamiento privado
    // (máx. 20 MiB). null = cancelado o error. Sin consumidor visual.
    private void openRenditionAttachment(
            java.util.function.Consumer<Map<String, Object>> result) {
        if (pendingRenditionAttachmentResult != null) {
            result.accept(null);
            return;
        }
        pendingRenditionAttachmentResult = result;
        final Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        startActivityForResult(intent, RENDITION_ATTACHMENT_REQUEST);
    }

    private Map<String, Object> copyRenditionAttachment(Uri uri) throws Exception {
        String name = displayName(uri).replaceAll("[^A-Za-z0-9._ -]", "_");
        if (name.isEmpty())
            name = "sustento";
        final File directory = new File(getFilesDir(), "renditions/attachments");
        if (!directory.exists() && !directory.mkdirs())
            throw new IllegalStateException("No se pudo crear la caché de sustentos.");
        File destination = new File(directory,
                System.currentTimeMillis() + "_" + name);
        long total = 0L;
        try (InputStream input = getContentResolver().openInputStream(uri);
             OutputStream output = new FileOutputStream(destination)) {
            if (input == null)
                throw new IllegalStateException("No se pudo leer el sustento.");
            final byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                total += count;
                if (total > 20L * 1024L * 1024L)
                    throw new IllegalArgumentException(
                            "El sustento supera el máximo de 20 MiB.");
                output.write(buffer, 0, count);
            }
        } catch (Throwable error) {
            if (destination.exists())
                destination.delete();
            throw error;
        }
        final String mime = getContentResolver().getType(uri);
        final Map<String, Object> metadata = new HashMap<>();
        metadata.put("localUri", Uri.fromFile(destination).toString());
        metadata.put("fileName", name);
        metadata.put("mimeType", mime == null ? "application/octet-stream" : mime);
        metadata.put("sizeBytes", total);
        return metadata;
    }

    private boolean openExternalUri(Object rawUri) {
        try {
            final String text = rawUri == null ? "" : rawUri.toString();
            final Uri uri = Uri.parse(text);
            final String scheme = uri.getScheme();
            if (!("https".equalsIgnoreCase(scheme)
                    || "http".equalsIgnoreCase(scheme)))
                return false;
            final Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            startActivity(intent);
            return true;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private void startEarthLocationSearch() {
        locationHandler.removeCallbacks(locationPoll);
        locationHandler.removeCallbacks(locationRefinePoll);
        bestLocationFix.clear();
        locationBestScore = Double.POSITIVE_INFINITY;
        locationLastObservedTimestamp = 0L;
        locationSearchStartedMs = SystemClock.elapsedRealtime();
        locationLastImprovedMs = locationSearchStartedMs;
        emitLocationStatus("searching", "Buscando GPS…");
        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            emitLocationStatus("permission", "Solicitando GPS preciso…");
            requestPermissions(new String[] {
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
            }, LOCATION_PERMISSION_REQUEST);
            return;
        }
        beginNativeLocationSearch();
    }

    private void beginNativeLocationSearch() {
        if (!InGeNativeLocation.start(this)) {
            String message = InGeNativeLocation.lastError();
            if (message == null || message.isEmpty())
                message = "No fue posible iniciar el GPS";
            emitLocationStatus("error", message);
            return;
        }
        locationSearchStartedMs = SystemClock.elapsedRealtime();
        locationLastImprovedMs = locationSearchStartedMs;
        locationHandler.post(locationPoll);
    }

    private void pollEarthLocation() {
        final long nowElapsed = SystemClock.elapsedRealtime();
        if (InGeNativeLocation.hasFix()) {
            final long timestamp = InGeNativeLocation.timestampMs();
            final double accuracy = InGeNativeLocation.accuracy();
            final long ageMs = Math.max(0L, System.currentTimeMillis() - timestamp);
            final String provider = InGeNativeLocation.provider();
            final boolean unseen = timestamp != locationLastObservedTimestamp;
            final boolean better = bestLocationFix.isEmpty()
                    || accuracy + 0.25 < locationBestScore;
            if (unseen) {
                locationLastObservedTimestamp = timestamp;
                if (better && ageMs <= 15_000L
                        && Double.isFinite(accuracy) && accuracy > 0.0) {
                    locationBestScore = accuracy;
                    locationLastImprovedMs = nowElapsed;
                    bestLocationFix.clear();
                    bestLocationFix.put("latitude", InGeNativeLocation.latitude());
                    bestLocationFix.put("longitude", InGeNativeLocation.longitude());
                    final double altitude = InGeNativeLocation.altitude();
                    if (Double.isFinite(altitude))
                        bestLocationFix.put("altitude", altitude);
                    bestLocationFix.put("accuracy", accuracy);
                    bestLocationFix.put("provider", provider);
                    bestLocationFix.put("timestampMs", timestamp);
                    bestLocationFix.put("ageMs", ageMs);
                    bestLocationFix.put("stale", ageMs > 15_000L);
                    bestLocationFix.put("final", false);
                    emitLocationFix(bestLocationFix);
                }
            }
        }
        final long elapsed = nowElapsed - locationSearchStartedMs;
        final Object accuracyObject = bestLocationFix.get("accuracy");
        final double bestAccuracy = accuracyObject instanceof Number
                ? ((Number) accuracyObject).doubleValue()
                : Double.POSITIVE_INFINITY;
        if (bestAccuracy <= 5.0 || elapsed >= LOCATION_TIMEBOX_MS) {
            finishEarthLocationSearch();
            return;
        }
        locationHandler.postDelayed(locationPoll, 500L);
    }

    private void finishEarthLocationSearch() {
        locationHandler.removeCallbacks(locationPoll);
        if (bestLocationFix.isEmpty()) {
            emitLocationStatus("error", "No se obtuvo un fix de ubicación en 8 s");
            // Keep tracking so a late cold-start fix still arrives; the
            // refinement poll releases GPS at the session bound.
            locationRefineUntilMs = locationSearchStartedMs + LOCATION_SESSION_MAX_MS;
            locationHandler.postDelayed(locationRefinePoll, 1_000L);
            return;
        }
        final Map<String, Object> result = new HashMap<>(bestLocationFix);
        final long timestamp = ((Number) result.get("timestampMs")).longValue();
        final long ageMs = Math.max(0L, System.currentTimeMillis() - timestamp);
        result.put("ageMs", ageMs);
        result.put("stale", ageMs > 15_000L);
        result.put("final", true);
        emitLocationFix(result);
        emitLocationStatus("complete", "Mejor fix GPS obtenido");
        locationRefineUntilMs = SystemClock.elapsedRealtime() + 15_000L;
        locationHandler.postDelayed(locationRefinePoll, 1_000L);
    }

    private void stopEarthLocationSearch() {
        locationHandler.removeCallbacks(locationPoll);
        locationHandler.removeCallbacks(locationRefinePoll);
        locationRefineUntilMs = 0L;
        InGeNativeLocation.stop();
    }

    private void pollEarthLocationRefinement() {
        final long nowElapsed = SystemClock.elapsedRealtime();
        if (nowElapsed > locationRefineUntilMs) {
            final long sessionEnd = locationSearchStartedMs + LOCATION_SESSION_MAX_MS;
            if (locationBestScore > LOCATION_PRECISE_M && nowElapsed < sessionEnd) {
                // Coarse (network) fix: let GNSS converge instead of restarting
                // it from zero on the next search.
                locationRefineUntilMs = sessionEnd;
            } else {
                // Nothing is emitted after refinement: release GPS/fused/network.
                InGeNativeLocation.stop();
                return;
            }
        }
        if (InGeNativeLocation.hasFix()) {
            final long timestamp = InGeNativeLocation.timestampMs();
            final double accuracy = InGeNativeLocation.accuracy();
            final long ageMs = Math.max(0L,
                    System.currentTimeMillis() - timestamp);
            if (timestamp != locationLastObservedTimestamp
                    && ageMs <= 15_000L
                    && Double.isFinite(accuracy) && accuracy > 0.0
                    && accuracy + 0.25 < locationBestScore) {
                locationLastObservedTimestamp = timestamp;
                locationBestScore = accuracy;
                final Map<String, Object> refined = new HashMap<>();
                refined.put("latitude", InGeNativeLocation.latitude());
                refined.put("longitude", InGeNativeLocation.longitude());
                final double altitude = InGeNativeLocation.altitude();
                if (Double.isFinite(altitude))
                    refined.put("altitude", altitude);
                refined.put("accuracy", accuracy);
                refined.put("provider", InGeNativeLocation.provider());
                refined.put("timestampMs", timestamp);
                refined.put("ageMs", ageMs);
                refined.put("stale", false);
                refined.put("final", true);
                bestLocationFix.clear();
                bestLocationFix.putAll(refined);
                emitLocationFix(refined);
                if (accuracy <= LOCATION_PRECISE_M)
                    locationRefineUntilMs = Math.min(locationRefineUntilMs,
                            nowElapsed + 15_000L);
            }
        }
        locationHandler.postDelayed(locationRefinePoll, 1_000L);
    }

    private void emitLocationStatus(String state, String message) {
        final Map<String, Object> payload = new HashMap<>();
        payload.put("state", state);
        payload.put("message", message);
        emitEarthUiJavascript("receiveNativeLocationStatus", payload);
    }

    private void emitLocationFix(Map<String, Object> fix) {
        emitEarthUiJavascript("receiveNativeLocation", fix);
    }

    private void emitEarthUiJavascript(String method, Map<String, Object> payload) {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded || method == null)
            return;
        final String json = new JSONObject(payload).toString();
        webView.evaluateJavascript(
                "window.InGeEarthUi&&window.InGeEarthUi."
                        + method + "(" + json + ");", null);
    }

    private void emitEarthProjectsJavascript(String method, String argument) {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded || method == null)
            return;
        final String script = "window.InGeEarthProjects&&window.InGeEarthProjects."
                + method + "(" + (argument == null ? "" : argument) + ");";
        webView.post(() -> webView.evaluateJavascript(script, null));
    }

    private void startEarthWebDocumentPicker() {
        if (pendingEarthWebImport) {
            emitEarthProjectsJavascript("receiveImportError",
                    JSONObject.quote("Ya existe una importación pendiente"));
            return;
        }
        pendingEarthWebImport = true;
        final Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                "application/vnd.google-earth.kml+xml",
                "application/vnd.google-earth.kmz",
                "application/xml", "text/xml", "application/zip"
        });
        startActivityForResult(intent, EARTH_IMPORT_REQUEST);
    }

    private void streamEarthDocumentToWeb(Uri uri) {
        renditionAttachmentExecutor.execute(() -> {
            try {
                final String name = displayName(uri);
                final String lower = name.toLowerCase(Locale.ROOT);
                if (!lower.endsWith(".kml") && !lower.endsWith(".kmz"))
                    throw new IllegalArgumentException(
                            "Selecciona un archivo .kml o .kmz");
                String mime = getContentResolver().getType(uri);
                if (mime == null || mime.isEmpty())
                    mime = lower.endsWith(".kmz")
                            ? "application/vnd.google-earth.kmz"
                            : "application/vnd.google-earth.kml+xml";
                final JSONObject metadata = new JSONObject();
                metadata.put("name", name);
                metadata.put("mime", mime);
                emitEarthProjectsJavascript("receiveImportStart",
                        metadata.toString());
                try (InputStream input =
                             getContentResolver().openInputStream(uri)) {
                    if (input == null)
                        throw new IllegalStateException(
                                "No se pudo leer el archivo seleccionado");
                    final byte[] buffer = new byte[192 * 1024];
                    int count;
                    while ((count = input.read(buffer)) >= 0) {
                        if (count == 0)
                            continue;
                        final byte[] chunk = new byte[count];
                        System.arraycopy(buffer, 0, chunk, 0, count);
                        final String encoded = android.util.Base64.encodeToString(
                                chunk, android.util.Base64.NO_WRAP);
                        emitEarthProjectsJavascript("receiveImportChunk",
                                JSONObject.quote(encoded));
                    }
                }
                emitEarthProjectsJavascript("receiveImportComplete", null);
            } catch (Throwable error) {
                emitEarthProjectsJavascript("receiveImportError",
                        JSONObject.quote(error.getMessage() == null
                                ? "No se pudo importar el archivo"
                                : error.getMessage()));
            }
        });
    }

    private String sanitizeEarthExportName(String value) {
        String name = value == null ? "Proyecto.kml"
                : value.replaceAll("[\\\\/:*?\"<>|]", "_").trim();
        if (name.isEmpty())
            name = "Proyecto.kml";
        return name.length() > 120 ? name.substring(0, 120) : name;
    }

    private synchronized void closePendingEarthWebExport() {
        if (pendingEarthWebExportStream != null) {
            try { pendingEarthWebExportStream.close(); }
            catch (Throwable ignored) {}
            pendingEarthWebExportStream = null;
        }
        if (pendingEarthWebExportFile != null
                && pendingEarthWebExportFile.exists())
            pendingEarthWebExportFile.delete();
        pendingEarthWebExportFile = null;
        pendingEarthWebExportName = null;
        pendingEarthWebExportMime = null;
        pendingEarthWebExport = false;
    }

    private void startEarthWebExportPicker() {
        if (pendingEarthWebExportFile == null
                || !pendingEarthWebExportFile.isFile()) {
            emitEarthExportResult(false, "La exportación no contiene datos");
            closePendingEarthWebExport();
            return;
        }
        pendingEarthWebExport = true;
        final Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(pendingEarthWebExportMime);
        intent.putExtra(Intent.EXTRA_TITLE, pendingEarthWebExportName);
        startActivityForResult(intent, EARTH_EXPORT_REQUEST);
    }

    private void writeEarthWebExport(Uri uri) throws Exception {
        try (InputStream input = new FileInputStream(pendingEarthWebExportFile);
             OutputStream output = getContentResolver().openOutputStream(uri)) {
            if (output == null)
                throw new IllegalStateException(
                        "No se pudo crear el archivo de destino");
            final byte[] buffer = new byte[192 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0)
                output.write(buffer, 0, count);
        }
    }

    private void emitEarthExportResult(boolean success, String message) {
        emitEarthProjectsJavascript("receiveExportResult",
                success + "," + JSONObject.quote(message == null ? "" : message));
    }

    private File earthDocumentsDirectory() {
        final File directory = new File(getFilesDir(), "earth/imports");
        if (!directory.exists())
            directory.mkdirs();
        return directory;
    }

    private List<Map<String, Object>> listEarthDocuments() {
        final List<Map<String, Object>> items = new ArrayList<>();
        final File[] files = earthDocumentsDirectory().listFiles();
        if (files == null)
            return items;
        for (File file : files) {
            final String lower = file.getName().toLowerCase(Locale.ROOT);
            if (!file.isFile() || (!lower.endsWith(".kml") && !lower.endsWith(".kmz")))
                continue;
            final Map<String, Object> item = new HashMap<>();
            item.put("id", file.getName());
            item.put("name", file.getName());
            item.put("path", file.getAbsolutePath());
            item.put("kmz", lower.endsWith(".kmz"));
            item.put("visible", true);
            items.add(item);
        }
        return items;
    }

    private String displayName(Uri uri) {
        try (Cursor cursor = getContentResolver().query(
                uri, new String[] {OpenableColumns.DISPLAY_NAME}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                final int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0)
                    return cursor.getString(index);
            }
        } catch (Throwable ignored) {}
        final String segment = uri.getLastPathSegment();
        return segment == null ? "earth.kml" : segment;
    }

    private Map<String, Object> copyEarthDocument(Uri uri) throws Exception {
        String name = displayName(uri).replaceAll("[^A-Za-z0-9._ -]", "_");
        final String lower = name.toLowerCase(Locale.ROOT);
        if (!lower.endsWith(".kml") && !lower.endsWith(".kmz"))
            throw new IllegalArgumentException("Selecciona un archivo .kml o .kmz");
        final File directory = earthDocumentsDirectory();
        File destination = new File(directory, name);
        final String base = name.substring(0, name.lastIndexOf('.'));
        final String extension = name.substring(name.lastIndexOf('.'));
        int suffix = 2;
        while (destination.exists())
            destination = new File(directory, base + " (" + suffix++ + ")" + extension);
        try (InputStream input = getContentResolver().openInputStream(uri);
             OutputStream output = new FileOutputStream(destination)) {
            if (input == null)
                throw new IllegalStateException("No se pudo leer el documento");
            final byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0)
                output.write(buffer, 0, count);
        }
        final Map<String, Object> item = new HashMap<>();
        item.put("id", destination.getName());
        item.put("name", destination.getName());
        item.put("path", destination.getAbsolutePath());
        item.put("kmz", destination.getName().toLowerCase(Locale.ROOT).endsWith(".kmz"));
        item.put("visible", true);
        return item;
    }

    private boolean removeEarthDocument(Object arguments) {
        final String id;
        if (arguments instanceof Map)
            id = String.valueOf(((Map<?, ?>) arguments).get("id"));
        else
            id = String.valueOf(arguments);
        final File directory = earthDocumentsDirectory();
        final File target = new File(directory, id);
        try {
            if (!target.getCanonicalFile().getParentFile().equals(directory.getCanonicalFile()))
                return false;
        } catch (Exception error) {
            return false;
        }
        return !target.exists() || target.delete();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (GoogleDriveAuthorization.onActivityResult(this, requestCode, resultCode, data)) return;
        if (requestCode == BIOMETRIC_AUTH_REQUEST && pendingBiometricResult != null) {
            final java.util.function.Consumer<Boolean> result = pendingBiometricResult;
            pendingBiometricResult = null;
            final boolean authenticated = resultCode == Activity.RESULT_OK
                    && data != null
                    && data.getBooleanExtra(
                            InGeBiometricActivity.EXTRA_AUTHENTICATED, false);
            result.accept(authenticated);
            return;
        }
        if (requestCode == RENDITION_ATTACHMENT_REQUEST
                && pendingRenditionAttachmentResult != null) {
            final java.util.function.Consumer<Map<String, Object>> result =
                    pendingRenditionAttachmentResult;
            if (resultCode != Activity.RESULT_OK || data == null
                    || data.getData() == null) {
                pendingRenditionAttachmentResult = null;
                result.accept(null);
                return;
            }
            final Uri selectedUri = data.getData();
            renditionAttachmentExecutor.execute(() -> {
                try {
                    final Map<String, Object> metadata =
                            copyRenditionAttachment(selectedUri);
                    runOnUiThread(() -> {
                        if (pendingRenditionAttachmentResult != result)
                            return;
                        pendingRenditionAttachmentResult = null;
                        result.accept(metadata);
                    });
                } catch (Throwable error) {
                    runOnUiThread(() -> {
                        if (pendingRenditionAttachmentResult != result)
                            return;
                        pendingRenditionAttachmentResult = null;
                        android.util.Log.w("InGeRenditions",
                                "INGE_ATTACHMENT_COPY_FAILED " + error.getClass().getSimpleName());
                        result.accept(null);
                    });
                }
            });
            return;
        }
        if (requestCode == EARTH_IMPORT_REQUEST && pendingEarthWebImport) {
            pendingEarthWebImport = false;
            if (resultCode == Activity.RESULT_OK && data != null
                    && data.getData() != null)
                streamEarthDocumentToWeb(data.getData());
            return;
        }
        if (requestCode == EARTH_EXPORT_REQUEST && pendingEarthWebExport) {
            if (resultCode != Activity.RESULT_OK || data == null
                    || data.getData() == null) {
                emitEarthExportResult(false, "Exportación cancelada");
                closePendingEarthWebExport();
                return;
            }
            try {
                writeEarthWebExport(data.getData());
                emitEarthExportResult(true, "Proyecto exportado");
            } catch (Throwable error) {
                emitEarthExportResult(false,
                        error.getMessage() == null
                                ? "No se pudo guardar la exportación"
                                : error.getMessage());
            } finally {
                closePendingEarthWebExport();
            }
            return;
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        // 8104 es propiedad del motor Earth (GPS nativo).
        if (requestCode == LOCATION_PERMISSION_REQUEST) {
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                    == PackageManager.PERMISSION_GRANTED) {
                emitLocationStatus("searching", "Buscando GPS…");
                beginNativeLocationSearch();
            } else if (checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                    == PackageManager.PERMISSION_GRANTED) {
                emitLocationStatus("error",
                        "Activa Ubicación precisa para mejorar la exactitud");
            } else {
                emitLocationStatus("error", "Permiso de ubicación precisa denegado");
            }
            return;
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
    }

    @Override
    public void onDestroy() {
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_DESTROY", null, null, null);
        performanceHandler.removeCallbacks(betaPerformanceSample);
        if (performanceRuntime != null)
            performanceRuntime.setBudgetListener(null);
        performanceHandler.removeCallbacks(releaseHiddenEarthRunnable);
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_DESTROY instance=" + System.identityHashCode(this));
        // Relaunch (config/core settings) vs real exit: process-global Qt state is
        // owned by QtActivityBase (retained on relaunch); only Activity-owned
        // resources (Earth WebView, pickers) are released below.
        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_RECREATE changingConfig="
                + isChangingConfigurations() + " finishing=" + isFinishing());
        activityResumed = false;
        if (pendingBiometricResult != null) {
            pendingBiometricResult.accept(false);
            pendingBiometricResult = null;
        }
        if (pendingRenditionAttachmentResult != null) {
            pendingRenditionAttachmentResult.accept(null);
            pendingRenditionAttachmentResult = null;
        }
        renditionAttachmentExecutor.shutdownNow();
        locationHandler.removeCallbacks(locationPoll);
        locationHandler.removeCallbacks(locationRefinePoll);
        closePendingEarthWebExport();
        pendingEarthWebImport = false;
        destroyDirectEarthWebView();
        current.clear();
        super.onDestroy();
    }

}
