package com.ingema.ingeplus;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.Context;
import android.content.pm.PackageManager;
import android.content.res.Configuration;
import android.database.Cursor;
import android.graphics.Color;
import android.graphics.Canvas;
import android.graphics.Path;
import android.graphics.Region;
import android.net.Uri;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Bundle;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.OpenableColumns;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.window.OnBackInvokedCallback;
import android.window.OnBackInvokedDispatcher;
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
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;
import androidx.webkit.WebViewAssetLoader;

import org.qtproject.qt.android.bindings.QtActivity;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.lang.ref.WeakReference;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.json.JSONObject;

import io.flutter.FlutterInjector;
import io.flutter.embedding.android.ExclusiveAppComponent;
import io.flutter.embedding.android.FlutterTextureView;
import io.flutter.embedding.android.FlutterSurfaceView;
import io.flutter.embedding.android.FlutterView;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugins.GeneratedPluginRegistrant;

/**
 * Qt owns the Activity and NavigationShellV51. Flutter remains shared by Home,
 * Auth and Renditions; Earth is a direct native Android WebView overlay.
 */
public final class InGeQtActivity extends QtActivity
        implements ExclusiveAppComponent<Activity>, LifecycleOwner {
    private static final String HOME_CHANNEL = "inge.home/host";
    private static final String RENDITIONS_CHANNEL = "inge.renditions/host";
    private static final String DOCK_CHANNEL = "inge.dock/context";
    private static final String EARTH_CHANNEL = "inge.earth/host";
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
    private static String pendingHomeAction = "";
    private static String pendingHomeAuthRequest = "";

    private final LifecycleRegistry flutterLifecycle = new LifecycleRegistry(this);

    private FlutterEngine homeEngine;
    private FlutterView homeView;
    private MethodChannel homeChannel;
    private MethodChannel renditionsChannel;
    private MethodChannel dockChannel;
    private int contextDockBandPx;
    // These are compositor apertures, not dock renderers. Qt owns every pixel
    // of the controls. Native content keeps its full viewport around them.
    private final float[] pendingDockGeometry = new float[9];
    private final float[] dockGeometry = new float[9];
    private final Path dockApertures = new Path();
    private final Region dockTouchRegion = new Region();
    private final Region dockRegionBounds = new Region();
    private boolean dockGeometryPosted;
    private boolean dockPathDirty = true;
    private int dockPathHeight = -1;
    private int dockPathWidth = -1;
    private final Runnable applyDockGeometry = new Runnable() {
        @Override public void run() {
            synchronized (pendingDockGeometry) {
                System.arraycopy(pendingDockGeometry, 0, dockGeometry, 0, 9);
                dockGeometryPosted = false;
            }
            dockPathDirty = true;
            if (homeView != null) homeView.invalidate();
            if (earthWebView != null) earthWebView.invalidate();
        }
    };
    private boolean homeReady;
    private boolean homeRequested;
    private boolean homeViewAttached;
    private boolean homeRendererActive;
    private long homeNavigationStartedMs;
    private String homeSurfaceMode = "home";
    private String homeAuthStateJson = "{}";
    private String lastSentHomeStateSignature;
    private MethodChannel.Result pendingBiometricResult;
    private MethodChannel.Result pendingRenditionAttachmentResult;
    private final ExecutorService renditionAttachmentExecutor =
            Executors.newSingleThreadExecutor();

    private FlutterEngine earthEngine;
    private FlutterView earthView;
    private MethodChannel earthChannel;
    private boolean earthReady;
    private boolean earthRequested;
    private boolean earthViewAttached;
    private boolean earthRendererActive;
    private WebView earthWebView;
    // Pantalla de carga cartográfica ÚNICA (InGe Earth y selector de Calicatas).
    private static final long MAP_LOADING_TIMEOUT_MS = 20_000L;
    private static final long MAP_LOADING_FADE_MS = 260L;
    private final Handler mapLoadingHandler = new Handler(Looper.getMainLooper());
    private final Runnable mapLoadingTimeout = this::onMapLoadingTimeout;
    private FrameLayout mapLoadingOverlay;
    private android.widget.ProgressBar mapLoadingSpinner;
    private android.widget.TextView mapLoadingText;
    private android.widget.TextView mapLoadingRetry;
    private boolean mapLoadingActive;
    private int mapLoadingSession = -1;
    private String mapLoadingType = "DEFAULT";
    private String mapLoadingReason = "";
    private long mapLoadingStartedAt;
    private InGeAssistantWebHost assistantHost;

    public static boolean showAssistant(String visuals) {
        final InGeQtActivity activity = current.get();
        if (activity == null) return false;
        activity.runOnUiThread(() -> {
            if (!activity.activityResumed) return;
            if (activity.assistantHost == null) activity.assistantHost = new InGeAssistantWebHost(activity);
            activity.assistantHost.open(visuals);
        });
        return true;
    }
    public static void closeAssistant() {
        final InGeQtActivity activity = current.get();
        if (activity != null) activity.runOnUiThread(() -> {
            if (activity.assistantHost != null) activity.assistantHost.close();
        });
    }
    public static void assistantMessage(String json) {
        final InGeQtActivity activity = current.get();
        if (activity != null) activity.runOnUiThread(() -> {
            if (activity.assistantHost != null) activity.assistantHost.message(json);
        });
    }
    private WebViewAssetLoader earthAssetLoader;
    private boolean earthWebViewLoaded;
    // Selector de coordenadas de Calicatas: el MISMO WebView/Cesium de Earth,
    // colocado sobre el área de mapa del selector Qt (nunca un segundo motor).
    private volatile boolean earthPickerActive;
    private boolean earthPickerSuspended;
    private String pendingEarthPickerJson = "";
    private final int[] earthPickerRect = new int[4];
    private String pendingEarthFocusJson = "";
    private volatile boolean earthBackTransitionInProgress;
    private volatile boolean earthHomeNavigationRequested;
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

    private String homeThemeMode = "light";
    private double homeMotionScale = 1.0;
    private double homeGlassIntensity = 0.72;
    private String homePerformanceProfile = "balanced";

    private final Handler locationHandler = new Handler(Looper.getMainLooper());
    private final Map<String, Object> bestLocationFix = new HashMap<>();
    private long locationSearchStartedMs;
    private long locationLastImprovedMs;
    private long locationLastObservedTimestamp;
    private double locationBestScore = Double.POSITIVE_INFINITY;
    private long locationRefineUntilMs;
    private MethodChannel.Result pendingImportResult;
    private MethodChannel.Result pendingExportResult;
    private String pendingExportKml;
    private boolean pendingEarthWebImport;
    private boolean pendingEarthWebExport;
    private File pendingEarthWebExportFile;
    private OutputStream pendingEarthWebExportStream;
    private String pendingEarthWebExportName;
    private String pendingEarthWebExportMime;

    private static native void nativeSubmitRenditionCommand(String requestJson);
    private static native void nativeRecordBetaDiagnostic(String eventJson);
    private static native boolean nativeRequestEarthBackToHome();
    private static native void nativeRequestGlobalBack();
    private static native void nativeDockPublish(String channel, String json);
    private static native void nativeDockClear(String channel, String ownerId);
    private static native void nativeDockComplete(String json);
    private static native void nativeDockBackdrop(String channel, String json);
    private OnBackInvokedCallback globalBackCallback;

    private void registerGlobalBackCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && globalBackCallback == null) {
            globalBackCallback = this::requestGlobalBack;
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT, globalBackCallback);
        }
    }

    private void requestGlobalBack() {
        if (assistantHost != null && assistantHost.isActive()) {
            assistantHost.closeFromUser();
            return;
        }
        android.util.Log.i("InGeNavigation", "INGE_BACK_RECEIVED source=ANDROID");
        nativeRequestGlobalBack();
    }

    // Called only with the decision made by Main.qml on the Qt thread.
    public static void completeGlobalBack(String action) {
        final InGeQtActivity activity = current.get();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            if ("EARTH".equals(action)) {
                activity.handleEarthBack();
            } else if ("RENDITIONS".equals(action)) {
                activity.dispatchRenditionsBackToFlutter();
            } else if ("EXIT_HOME".equals(action)) {
                activity.exitFromHome();
            }
        });
    }

    private void exitFromHome() {
        super.onBackPressed();
    }

    private static native void nativeEarthPickerSelected(double latitude, double longitude);
    private static native void nativeEarthPickerState(String state);
    private static native void nativeEarthPickerSnapshot(String mapType, double latitude,
            double longitude, String dataUrl);

    private static native boolean nativeUseEarthPointInCalicata(
            double latitude, double longitude, double altitude, double accuracy,
            String timestamp, String source);

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

    public static boolean focusEarthCoordinate(double latitude, double longitude,
                                                double altitude, String label) {
        final InGeQtActivity activity = current.get();
        if (activity == null || !Double.isFinite(latitude)
                || !Double.isFinite(longitude)
                || latitude < -90.0 || latitude > 90.0
                || longitude < -180.0 || longitude > 180.0)
            return false;
        final Map<String, Object> coordinate = new HashMap<>();
        coordinate.put("latitude", latitude);
        coordinate.put("longitude", longitude);
        coordinate.put("altitude", Double.isFinite(altitude) ? altitude : 0.0);
        coordinate.put("label", label == null ? "Calicata" : label);
        final String json = new JSONObject(coordinate).toString();
        activity.runOnUiThread(() -> {
            activity.pendingEarthFocusJson = json;
            activity.deliverPendingEarthFocus();
        });
        return true;
    }

    // Host dock adapters: native surfaces publish semantic context and receive
    // commands; the single QML dock owns the band they leave uncovered.
    public static boolean deliverContextCommand(String channel, String json) {
        final InGeQtActivity activity = current.get();
        if (activity == null || channel == null || json == null)
            return false;
        if (!"flutter".equals(channel) && !"earth".equals(channel))
            return false;
        activity.runOnUiThread(() -> activity.routeContextCommand(channel, json));
        return true;
    }

    public static void setContextDockBand(int px) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return;
        final int band = Math.max(0, Math.min(px, 1200));
        activity.runOnUiThread(() -> {
            activity.contextDockBandPx = band;
            activity.configureHomeViewInsets();
            activity.applyContextDockBand(activity.earthWebView);
        });
    }

    public static void setContextDockGeometry(float left, float width, float height,
            float bottom, float coreSize, float gap, float searchWidth,
            float searchHeight, float searchGap) {
        final InGeQtActivity activity = current.get();
        if (activity == null) return;
        // QML supplies animated scalar positions. Reuse storage and one UI
        // runnable; never allocate a bitmap, renderer, or animation per frame.
        synchronized (activity.pendingDockGeometry) {
            final float[] g = activity.pendingDockGeometry;
            g[0] = left; g[1] = width; g[2] = height; g[3] = bottom;
            g[4] = coreSize; g[5] = gap; g[6] = searchWidth;
            g[7] = searchHeight; g[8] = searchGap;
            if (!activity.dockGeometryPosted) {
                activity.dockGeometryPosted = true;
                activity.runOnUiThread(activity.applyDockGeometry);
            }
        }
    }

    private void updateDockApertures(int viewWidth, int viewHeight) {
        if (!dockPathDirty && dockPathHeight == viewHeight && dockPathWidth == viewWidth) return;
        dockPathDirty = false;
        dockPathHeight = viewHeight;
        dockPathWidth = viewWidth;
        dockApertures.rewind();
        dockTouchRegion.setEmpty();
        final float[] g = dockGeometry;
        for (float value : g)
            if (Float.isNaN(value) || Float.isInfinite(value)) return;
        if (viewWidth <= 0 || viewHeight <= 0 || g[1] <= 0 || g[2] <= 0
                || g[3] < 0 || g[4] < 0 || g[5] < 0 || g[6] < 0
                || g[7] < 0 || g[8] < 0) return;
        final float top = viewHeight - g[3] - g[2];
        dockApertures.addRoundRect(g[0], top, g[0] + g[1], top + g[2],
                g[2] / 2, g[2] / 2, Path.Direction.CW);
        final float coreLeft = g[0] + g[1] + g[5];
        final float coreTop = top + (g[2] - g[4]) / 2;
        dockApertures.addRoundRect(coreLeft, coreTop, coreLeft + g[4], coreTop + g[4],
                g[4] / 2, g[4] / 2, Path.Direction.CW);
        if (g[6] > 0) {
            final float searchLeft = g[0] + (g[1] - g[6]) / 2;
            final float searchTop = top - g[8] - g[7];
            dockApertures.addRoundRect(searchLeft, searchTop, searchLeft + g[6],
                    searchTop + g[7], g[7] / 2, g[7] / 2, Path.Direction.CW);
        }
        dockRegionBounds.set(0, 0, viewWidth, viewHeight);
        dockTouchRegion.setPath(dockApertures, dockRegionBounds);
    }

    @SuppressWarnings("deprecation")
    private void clipNativeDock(Canvas canvas, int viewWidth, int viewHeight) {
        updateDockApertures(viewWidth, viewHeight);
        if (Build.VERSION.SDK_INT >= 26)
            canvas.clipOutPath(dockApertures);
        else
            canvas.clipPath(dockApertures, Region.Op.DIFFERENCE);
    }

    private boolean dockOwnsTouch(MotionEvent event, int viewWidth, int viewHeight) {
        updateDockApertures(viewWidth, viewHeight);
        return dockTouchRegion.contains((int) event.getX(), (int) event.getY());
    }

    private void routeContextCommand(String channel, String json) {
        if ("flutter".equals(channel)) {
            if (dockChannel != null)
                dockChannel.invokeMethod("command", json);
            return;
        }
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded)
            return;
        webView.evaluateJavascript(
                "window.InGeEarthContext&&window.InGeEarthContext.command("
                        + JSONObject.quote(json) + ");", null);
    }

    private void applyContextDockBand(View view) {
        if (view == null)
            return;
        final ViewGroup.LayoutParams rawParams = view.getLayoutParams();
        if (!(rawParams instanceof FrameLayout.LayoutParams))
            return;
        final FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) rawParams;
        if (params.bottomMargin == contextDockBandPx)
            return;
        params.bottomMargin = contextDockBandPx;
        view.setLayoutParams(params);
    }

    @Override
    @NonNull
    public Activity getAppComponent() {
        return this;
    }

    @Override
    public void detachFromFlutterEngine() {
        // Each persistent engine is owned by this Activity for its full life.
    }

    @Override
    @NonNull
    public Lifecycle getLifecycle() {
        return flutterLifecycle;
    }

    // Mapa base de InGe Earth (DEFAULT_MAP_URL): la vista previa Qt de
    // Calicatas usa el mismo servidor de teselas que Cesium.
    public static String getEarthDefaultMapUrl() {
        final String url = BuildConfig.DEFAULT_MAP_URL;
        return url == null ? "" : url.trim();
    }

    public static boolean isEarthAvailable() {
        return current.get() != null;
    }

    public static boolean setFlutterHomeVisible(
            boolean visible,
            String themeMode,
            double motionScale,
            double glassIntensity,
            String performanceProfile) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return false;
        // Home, Auth y Seguridad comparten este engine/surface. Una orden de
        // ocultar Home no puede aparcar la superficie mientras Auth o Seguridad
        // son sus propietarios visibles.
        if (!visible && !"home".equals(activity.homeSurfaceMode)) {
            android.util.Log.i("InGeFlutterAuth",
                    "AUTH_HOME_HIDE_IGNORED owner=" + activity.homeSurfaceMode);
            return true;
        }
        activity.homeThemeMode = themeMode == null ? "light" : themeMode;
        activity.homeMotionScale = motionScale;
        activity.homeGlassIntensity = glassIntensity;
        activity.homePerformanceProfile = performanceProfile == null
                ? "balanced" : performanceProfile;
        if (visible && !"home".equals(activity.homeSurfaceMode))
            android.util.Log.i("InGeFlutterAuth", "AUTH_OWNER from="
                    + activity.homeSurfaceMode + " to=home");
        activity.homeSurfaceMode = "home";
        activity.homeRequested = visible;
        if (visible && activity.earthBackTransitionInProgress)
            activity.earthHomeNavigationRequested = true;
        if (visible) activity.markNavigationStart("home");
        if (visible && activity.performanceRuntime != null)
            activity.performanceRuntime.setState(InGePerformanceRuntime.State.HOME);
        activity.runOnUiThread(() -> activity.applyFlutterHomeVisibility(visible));
        return true;
    }

    public static boolean setFlutterRenditionsVisible(
            boolean visible,
            String themeMode,
            double motionScale,
            double glassIntensity,
            String performanceProfile) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return false;
        if (!visible) {
            if (!"renditions".equals(activity.homeSurfaceMode))
                return true;
            activity.homeRequested = false;
            activity.homeSurfaceMode = "home";
            activity.runOnUiThread(
                    () -> activity.applyFlutterHomeVisibility(false));
            return true;
        }
        activity.homeSurfaceMode = "renditions";
        activity.homeThemeMode = "dark".equals(themeMode) ? "dark" : "light";
        activity.homeMotionScale = motionScale;
        activity.homeGlassIntensity = glassIntensity;
        activity.homePerformanceProfile = performanceProfile == null
                ? "balanced" : performanceProfile;
        activity.homeRequested = true;
        activity.markNavigationStart("renditions");
        if (activity.performanceRuntime != null)
            activity.performanceRuntime.setState(InGePerformanceRuntime.State.RENDICIONES);
        activity.runOnUiThread(() -> activity.applyFlutterHomeVisibility(true));
        return true;
    }

    public static void dispatchRenditionEvent(String eventJson) {
        final InGeQtActivity activity = current.get();
        if (activity == null || eventJson == null)
            return;
        activity.runOnUiThread(() -> {
            if (activity.renditionsChannel != null)
                activity.renditionsChannel.invokeMethod("renditionEvent", eventJson);
        });
    }

    public static boolean setFlutterAuthVisible(
            boolean visible,
            String authStateJson,
            String themeMode,
            double motionScale,
            double glassIntensity,
            String performanceProfile) {
        return setFlutterAuthSurfaceVisible(
                "auth", visible, authStateJson, themeMode, motionScale,
                glassIntensity, performanceProfile);
    }

    public static boolean setFlutterSecurityVisible(
            boolean visible,
            String authStateJson,
            String themeMode,
            double motionScale,
            double glassIntensity,
            String performanceProfile) {
        return setFlutterAuthSurfaceVisible(
                "security", visible, authStateJson, themeMode, motionScale,
                glassIntensity, performanceProfile);
    }

    private static boolean setFlutterAuthSurfaceVisible(
            String surfaceMode,
            boolean visible,
            String authStateJson,
            String themeMode,
            double motionScale,
            double glassIntensity,
            String performanceProfile) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return false;
        if (!visible) {
            // Ocultar Auth/Seguridad solo libera la superficie si ese modo es
            // su propietario actual. Antes, esta orden reclamaba la propiedad
            // ("auth") al ocultar: Home ya presentado quedaba aparcado y sus
            // órdenes posteriores terminaban en AUTH_HOME_HIDE_IGNORED.
            if (!surfaceMode.equals(activity.homeSurfaceMode)) {
                android.util.Log.i("InGeFlutterAuth", "AUTH_OWNER_HIDE_IGNORED surface="
                        + surfaceMode + " owner=" + activity.homeSurfaceMode);
                return true;
            }
            android.util.Log.i("InGeFlutterAuth", "AUTH_OWNER from="
                    + surfaceMode + " to=none");
            // Propiedad neutra: la vista queda aparcada y la próxima orden de
            // Home (o de Auth) la reclama explícitamente.
            activity.homeSurfaceMode = "home";
            activity.homeRequested = false;
            activity.runOnUiThread(() -> activity.applyFlutterHomeVisibility(false));
            return true;
        }
        if (!surfaceMode.equals(activity.homeSurfaceMode))
            android.util.Log.i("InGeFlutterAuth", "AUTH_OWNER from="
                    + activity.homeSurfaceMode + " to=" + surfaceMode);
        activity.homeSurfaceMode = surfaceMode;
        activity.homeAuthStateJson = authStateJson == null ? "{}" : authStateJson;
        activity.homeThemeMode = "dark".equals(themeMode) ? "dark" : "light";
        activity.homeMotionScale = motionScale;
        activity.homeGlassIntensity = glassIntensity;
        activity.homePerformanceProfile = performanceProfile == null
                ? "balanced" : performanceProfile;
        activity.homeRequested = visible;
        if (visible && "auth".equals(surfaceMode))
            android.util.Log.i("InGeFlutterAuth", "AUTH_FLUTTER_VISIBLE_REQUEST");
        activity.runOnUiThread(() -> activity.applyFlutterHomeVisibility(visible));
        return true;
    }

    public static boolean updateFlutterAuthState(String authStateJson) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return false;
        final String nextState = authStateJson == null ? "{}" : authStateJson;
        if (nextState.equals(activity.homeAuthStateJson))
            return true;
        activity.homeAuthStateJson = nextState;
        activity.runOnUiThread(activity::sendHomeSurfaceState);
        return true;
    }

    public static boolean setDirectEarthVisible(boolean visible) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return false;
        // Durante Back, el host Qt cierra Earth para publicar CLOSED. La
        // propiedad Android debe seguir activa hasta que Home esté presentado,
        // porque también mantiene dueño al callback predictivo transitorio.
        if (visible || !activity.earthBackTransitionInProgress)
            activity.earthRequested = visible;
        activity.runOnUiThread(() -> activity.applyDirectEarthVisibility(visible));
        return true;
    }

    // Rect en píxeles de pantalla (coordenadas globales de la ventana Qt).
    public static boolean showEarthPicker(String json, int left, int top, int width, int height) {
        final InGeQtActivity activity = current.get();
        if (activity == null || width <= 0 || height <= 0)
            return false;
        final String payload = json == null ? "{}" : json;
        activity.runOnUiThread(() -> activity.enterEarthPicker(payload, left, top, width, height));
        return true;
    }

    public static void updateEarthPickerRect(int left, int top, int width, int height) {
        final InGeQtActivity activity = current.get();
        if (activity == null || width <= 0 || height <= 0)
            return;
        activity.runOnUiThread(() -> {
            if (!activity.earthPickerActive)
                return;
            activity.earthPickerRect[0] = left;
            activity.earthPickerRect[1] = top;
            activity.earthPickerRect[2] = width;
            activity.earthPickerRect[3] = height;
            activity.applyEarthPickerLayout();
        });
    }

    public static void setEarthPickerPoint(String json) {
        final InGeQtActivity activity = current.get();
        if (activity == null || json == null || json.length() > 2048)
            return;
        activity.runOnUiThread(() -> activity.runEarthPickerScript(
                "window.InGeEarthPicker&&window.InGeEarthPicker.setPoint(" + JSONObject.quote(json) + ");"));
    }

    // Diálogos Qt que se superponen al mapa: el WebView se oculta sin perder estado.
    public static void setEarthPickerSuspended(boolean suspended) {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return;
        activity.runOnUiThread(() -> {
            activity.earthPickerSuspended = suspended;
            if (activity.earthPickerActive && activity.earthWebView != null)
                activity.earthWebView.setVisibility(suspended ? View.INVISIBLE : View.VISIBLE);
                activity.syncMapLoadingLayout();
        });
    }

    public static void hideEarthPicker() {
        final InGeQtActivity activity = current.get();
        if (activity == null)
            return;
        activity.runOnUiThread(activity::exitEarthPicker);
    }

    private void enterEarthPicker(String json, int left, int top, int width, int height) {
        if (earthRequested) {
            // InGe Earth a pantalla completa ya usa el viewer: no se comparte a la vez.
            notifyEarthPickerState("ERROR_EARTH_ACTIVE");
            return;
        }
        try {
            ensureDirectEarthWebView();
        } catch (Throwable error) {
            android.util.Log.e("InGeEarthPicker", "INGE_EARTH_PICKER_WEBVIEW_FAILED", error);
            notifyEarthPickerState("ERROR_WEBVIEW");
            return;
        }
        earthPickerActive = true;
        earthPickerSuspended = false;
        earthPickerRect[0] = left;
        earthPickerRect[1] = top;
        earthPickerRect[2] = width;
        earthPickerRect[3] = height;
        pendingEarthPickerJson = json;
        applyEarthPickerLayout();
        earthWebView.animate().cancel();
        earthWebView.setAlpha(1.0f);
        earthWebView.onResume();
        earthWebView.setEnabled(true);
        earthWebView.setVisibility(View.VISIBLE);
        earthWebView.bringToFront();
        showMapLoading("picker");
        notifyEarthPickerState(earthWebViewLoaded ? "LOADING_VIEW" : "LOADING_ENGINE");
        deliverPendingEarthPicker();
        android.util.Log.i("InGeEarthPicker", "INGE_EARTH_PICKER_SHOWN loaded=" + earthWebViewLoaded
                + " rect=" + width + "x" + height);
    }

    private void applyEarthPickerLayout() {
        final WebView webView = earthWebView;
        if (webView == null || !earthPickerActive)
            return;
        final FrameLayout content = findViewById(android.R.id.content);
        final int[] origin = new int[2];
        if (content != null)
            content.getLocationOnScreen(origin);
        final FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                earthPickerRect[2], earthPickerRect[3], Gravity.TOP | Gravity.START);
        params.leftMargin = Math.max(0, earthPickerRect[0] - origin[0]);
        params.topMargin = Math.max(0, earthPickerRect[1] - origin[1]);
        webView.setLayoutParams(params);
        syncMapLoadingLayout();
    }

    private void deliverPendingEarthPicker() {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded || !earthPickerActive
                || pendingEarthPickerJson.isEmpty())
            return;
        final String json = pendingEarthPickerJson;
        pendingEarthPickerJson = "";
        webView.evaluateJavascript(
                "(function(){return !!(window.InGeEarthPicker&&window.InGeEarthPicker.enter("
                        + JSONObject.quote(json) + "));})();",
                result -> notifyEarthPickerState("true".equals(result) ? "READY" : "ERROR_SCRIPT"));
    }

    private void runEarthPickerScript(String script) {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded || !earthPickerActive)
            return;
        webView.evaluateJavascript(script, null);
    }

    private void exitEarthPicker() {
        if (!earthPickerActive)
            return;
        earthPickerActive = false;
        earthPickerSuspended = false;
        pendingEarthPickerJson = "";
        cancelMapLoading("picker_closed");
        final WebView webView = earthWebView;
        if (webView != null) {
            if (earthWebViewLoaded)
                webView.evaluateJavascript(
                        "window.InGeEarthPicker&&window.InGeEarthPicker.exit();", null);
            webView.setVisibility(View.GONE);
            webView.setEnabled(false);
            webView.setLayoutParams(new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    Gravity.TOP | Gravity.START));
            applyContextDockBand(webView);
            webView.onPause();
        }
        notifyEarthPickerState("CLOSED");
        android.util.Log.i("InGeEarthPicker", "INGE_EARTH_PICKER_HIDDEN");
    }

    private void ensureMapLoadingOverlay() {
        if (mapLoadingOverlay != null)
            return;
        final float dp = getResources().getDisplayMetrics().density;
        final FrameLayout overlay = new FrameLayout(this);
        overlay.setBackgroundColor(Color.rgb(0xEE, 0xF3, 0xF8));
        overlay.setClickable(true);      // el mapa no recibe toques mientras carga
        overlay.setFocusable(true);
        overlay.setContentDescription("Cargando mapa");
        final android.widget.LinearLayout column = new android.widget.LinearLayout(this);
        column.setOrientation(android.widget.LinearLayout.VERTICAL);
        column.setGravity(Gravity.CENTER_HORIZONTAL);
        final android.widget.ProgressBar spinner = new android.widget.ProgressBar(this);
        spinner.setIndeterminate(true);
        spinner.setIndeterminateTintList(android.content.res.ColorStateList.valueOf(
                Color.rgb(0x1F, 0x6F, 0xB2)));
        column.addView(spinner, new android.widget.LinearLayout.LayoutParams(
                Math.round(40 * dp), Math.round(40 * dp)));
        final android.widget.TextView text = new android.widget.TextView(this);
        text.setText("Cargando mapa…");
        text.setTextColor(Color.rgb(0x33, 0x41, 0x55));
        text.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15);
        text.setGravity(Gravity.CENTER);
        final android.widget.LinearLayout.LayoutParams textParams =
                new android.widget.LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        textParams.topMargin = Math.round(12 * dp);
        column.addView(text, textParams);
        final android.widget.TextView retry = new android.widget.TextView(this);
        retry.setText("Reintentar");
        retry.setTextColor(Color.WHITE);
        retry.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 15);
        retry.setGravity(Gravity.CENTER);
        final android.graphics.drawable.GradientDrawable pill =
                new android.graphics.drawable.GradientDrawable();
        pill.setColor(Color.rgb(0x1F, 0x6F, 0xB2));
        pill.setCornerRadius(22 * dp);
        retry.setBackground(pill);
        retry.setPadding(Math.round(22 * dp), Math.round(10 * dp),
                Math.round(22 * dp), Math.round(10 * dp));
        retry.setVisibility(View.GONE);
        retry.setOnClickListener(view -> retryMapLoading("user"));
        final android.widget.LinearLayout.LayoutParams retryParams =
                new android.widget.LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT, Math.round(44 * dp));
        retryParams.topMargin = Math.round(16 * dp);
        column.addView(retry, retryParams);
        overlay.addView(column, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER));
        overlay.setVisibility(View.GONE);
        final FrameLayout content = findViewById(android.R.id.content);
        content.addView(overlay, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.TOP | Gravity.START));
        mapLoadingOverlay = overlay;
        mapLoadingSpinner = spinner;
        mapLoadingText = text;
        mapLoadingRetry = retry;
    }

    // Misma geometría y visibilidad que el WebView (selector: rectángulo; Earth: pantalla).
    private void syncMapLoadingLayout() {
        final FrameLayout overlay = mapLoadingOverlay;
        final WebView webView = earthWebView;
        if (overlay == null || !mapLoadingActive || webView == null)
            return;
        final ViewGroup.LayoutParams source = webView.getLayoutParams();
        if (source instanceof FrameLayout.LayoutParams)
            overlay.setLayoutParams(new FrameLayout.LayoutParams((FrameLayout.LayoutParams) source));
        overlay.setVisibility(webView.getVisibility() == View.VISIBLE ? View.VISIBLE : View.INVISIBLE);
        overlay.bringToFront();
    }

    private void showMapLoading(String reason) {
        ensureMapLoadingOverlay();
        final boolean restart = !mapLoadingActive;
        mapLoadingActive = true;
        mapLoadingSession = -1;          // acepta solo el BEGIN de la sesión nueva
        mapLoadingReason = reason;
        if (restart)
            mapLoadingStartedAt = SystemClock.uptimeMillis();
        mapLoadingOverlay.animate().cancel();
        mapLoadingOverlay.setAlpha(1.0f);
        mapLoadingSpinner.setVisibility(View.VISIBLE);
        mapLoadingText.setText("Cargando mapa…");
        mapLoadingRetry.setVisibility(View.GONE);
        syncMapLoadingLayout();
        mapLoadingHandler.removeCallbacks(mapLoadingTimeout);
        mapLoadingHandler.postDelayed(mapLoadingTimeout, MAP_LOADING_TIMEOUT_MS);
        if (restart)
            android.util.Log.i("InGeMapLoading", "INGE_MAP_LOAD_BEGIN reason=" + reason);
    }

    private void onMapLoadingEvent(String state, int session, String type, int jsMs) {
        if ("CANCELLED".equals(state))
            return;                      // la cancelación la decide el host
        if ("BEGIN".equals(state)) {
            if (!mapLoadingActive)
                showMapLoading("layer");  // Mapa <-> Satélite o salto programático
            mapLoadingSession = session;
            mapLoadingType = type;
            return;
        }
        if (!mapLoadingActive || session != mapLoadingSession) {
            android.util.Log.i("InGeMapLoading", "INGE_MAP_STALE_EVENT " + state + " session=" + session);
            return;
        }
        final long ms = SystemClock.uptimeMillis() - mapLoadingStartedAt;
        android.util.Log.i("InGeMapLoading", "INGE_MAP_" + state + " ms=" + ms + " sessionMs=" + jsMs
                + " type=" + type + " reason=" + mapLoadingReason);
        if ("VISUAL_READY".equals(state))
            revealMapLoading();
    }

    private void revealMapLoading() {
        mapLoadingActive = false;
        mapLoadingHandler.removeCallbacks(mapLoadingTimeout);
        final FrameLayout overlay = mapLoadingOverlay;
        if (overlay == null)
            return;
        final long ms = SystemClock.uptimeMillis() - mapLoadingStartedAt;
        final String type = mapLoadingType;
        final Runnable revealed = () -> {
            overlay.setVisibility(View.GONE);
            android.util.Log.i("InGeMapLoading", "INGE_MAP_REVEALED ms=" + ms + " type=" + type);
        };
        overlay.animate().cancel();
        // Movimiento reducido (escala de animación 0): retirada inmediata.
        if (!android.animation.ValueAnimator.areAnimatorsEnabled()
                || overlay.getVisibility() != View.VISIBLE) {
            revealed.run();
            return;
        }
        overlay.animate().alpha(0.0f).setDuration(MAP_LOADING_FADE_MS)
                .setInterpolator(new android.view.animation.DecelerateInterpolator(1.2f))
                .withEndAction(revealed).start();
    }

    private void onMapLoadingTimeout() {
        if (!mapLoadingActive || mapLoadingOverlay == null)
            return;
        android.util.Log.w("InGeMapLoading", "INGE_MAP_LOAD_TIMEOUT ms="
                + (SystemClock.uptimeMillis() - mapLoadingStartedAt) + " type=" + mapLoadingType
                + " reason=" + mapLoadingReason);
        mapLoadingSpinner.setVisibility(View.GONE);
        mapLoadingText.setText("El mapa tarda en cargar. Revisa la conexión.");
        mapLoadingRetry.setVisibility(View.VISIBLE);
    }

    private void retryMapLoading(String why) {
        if (!mapLoadingActive)
            return;
        mapLoadingStartedAt = SystemClock.uptimeMillis();
        showMapLoading(mapLoadingReason);
        final WebView webView = earthWebView;
        if (webView == null)
            return;
        if (!earthWebViewLoaded) {
            if ("user".equals(why))
                webView.reload();
            return;
        }
        webView.evaluateJavascript("(window.InGeEarthPicker&&window.InGeEarthPicker.isActive()"
                + "&&window.InGeEarthPicker.reload())"
                + "||(window.InGeMapLoading&&window.InGeMapLoading.retry());", null);
    }

    private void cancelMapLoading(String reason) {
        mapLoadingHandler.removeCallbacks(mapLoadingTimeout);
        if (!mapLoadingActive)
            return;
        mapLoadingActive = false;
        mapLoadingSession = -1;
        if (mapLoadingOverlay != null) {
            mapLoadingOverlay.animate().cancel();
            mapLoadingOverlay.setVisibility(View.GONE);
        }
        android.util.Log.i("InGeMapLoading", "INGE_MAP_LOAD_CANCELLED ms="
                + (SystemClock.uptimeMillis() - mapLoadingStartedAt) + " reason=" + reason);
        final WebView webView = earthWebView;
        if (webView != null && earthWebViewLoaded)
            webView.evaluateJavascript("window.InGeMapLoading&&window.InGeMapLoading.cancel();", null);
    }

    private void notifyEarthPickerState(String state) {
        try {
            nativeEarthPickerState(state);
        } catch (Throwable error) {
            android.util.Log.e("InGeEarthPicker", "INGE_EARTH_PICKER_STATE_FAILED", error);
        }
    }

    public static boolean isFlutterHomeReady() {
        final InGeQtActivity activity = current.get();
        return activity != null && activity.homeReady && activity.homeView != null;
    }

    public static synchronized String takeFlutterHomeAction() {
        final String action = pendingHomeAction;
        pendingHomeAction = "";
        return action;
    }

    public static synchronized String takeFlutterAuthRequest() {
        final String request = pendingHomeAuthRequest;
        pendingHomeAuthRequest = "";
        return request;
    }

    private static synchronized void postFlutterHomeAction(String action) {
        if (pendingHomeAction.isEmpty())
            pendingHomeAction = action == null ? "" : action;
    }

    private static synchronized void postFlutterAuthRequest(String request) {
        if (pendingHomeAuthRequest.isEmpty())
            pendingHomeAuthRequest = request == null ? "" : request;
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
        registerGlobalBackCallback();
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
        // Flutter (Auth/Home) is the first surface after Qt loads Main.qml.
        // startInitialization only queues libflutter/libapp loading on
        // Flutter's own background executor; the later entrypoint() then
        // waits on the UI thread only for what is still pending, overlapping
        // it with Qt's startup. Idempotent: entrypoint() calls it again.
        try {
            FlutterInjector.instance().flutterLoader()
                    .startInitialization(getApplicationContext());
            android.util.Log.i("InGePerformance",
                    "INGE_FLUTTER_PREWARM=LOADER_STARTED");
        } catch (Throwable error) {
            android.util.Log.w("InGePerformance",
                    "INGE_FLUTTER_PREWARM=FAILED", error);
        }
        flutterLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_CREATE);
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
        if (earthRequested)
            android.util.Log.i("InGeEarth", "EARTH_HOST_RESUMED");
        if (performanceRuntime != null)
            performanceRuntime.setTrackingEnabled(true);
        flutterLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_RESUME);
        if (homeEngine != null && !homeRequested)
            homeEngine.getLifecycleChannel().appIsPaused();
        if (homeRequested && homeEngine != null && homeView != null)
            resumeFlutterViewAfterActivityResume(homeView);
        if (mapLoadingActive) {
            mapLoadingHandler.removeCallbacks(mapLoadingTimeout);
            mapLoadingHandler.postDelayed(mapLoadingTimeout, MAP_LOADING_TIMEOUT_MS);
            retryMapLoading("resume");
        }
        if (earthPickerActive && earthWebView != null) {
            earthWebView.onResume();
            earthWebView.setVisibility(earthPickerSuspended ? View.INVISIBLE : View.VISIBLE);
            applyEarthPickerLayout();
        }
        if (earthRequested)
            applyDirectEarthVisibility(true);
        else if (homeRequested && homeEngine == null)
            applyFlutterHomeVisibility(true);
    }

    @Override
    protected void onPause() {
        if (assistantHost != null) assistantHost.pause();
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_PAUSE instance=" + System.identityHashCode(this));
        activityResumed = false;
        mapLoadingHandler.removeCallbacks(mapLoadingTimeout);
        emitBetaPerformanceSample();
        performanceHandler.removeCallbacks(betaPerformanceSample);
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_PAUSE", null, null, null);
        if (earthRequested)
            android.util.Log.i("InGeEarth", "EARTH_HOST_PAUSED");
        if (performanceRuntime != null)
            performanceRuntime.setTrackingEnabled(false);
        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_ON_PAUSE_BEGIN");

        // P0: Qt debe recibir el pause inmediatamente. Antes este super.onPause()
        // se ejecutaba DESPUES de callbacks Flutter, dejando al render thread Qt
        // presentando un frame cuando Android ya estaba retirando la Surface.
        super.onPause();

        flutterLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE);
        pauseFlutterViewForActivity(homeView, homeRequested);
        if (earthRequested && earthWebView != null) {
            emitEarthPageVisibility(false);
            stopEarthLocationSearch();
            earthWebView.onPause();
        } else if (earthPickerActive && earthWebView != null) {
            earthWebView.onPause();
        }

        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_ON_PAUSE_END");
    }

    @Override
    protected void onStop() {
        if (assistantHost != null && assistantHost.isActive()) assistantHost.closeFromUser();
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_STOP", null, null, null);
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_STOP instance=" + System.identityHashCode(this));
        super.onStop();
    }

    // Android 14+ only delivers TRIM_MEMORY_UI_HIDDEN and _BACKGROUND; older
    // versions also RUNNING_LOW/CRITICAL while in the foreground. This host
    // is not a FlutterActivity, so the engines get the signal from here.
    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        android.util.Log.i("InGePerformance", "INGE_TRIM_MEMORY level=" + level
                + " earthRequested=" + earthRequested
                + " earthAlive=" + (earthWebView != null));
        if (performanceRuntime != null)
            performanceRuntime.onTrimMemory(level);
        notifyFlutterMemoryPressure(homeEngine, level);
        notifyFlutterMemoryPressure(earthEngine, level);
        if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
            releaseHiddenEarthWebView("trim_" + level);
    }

    @Override
    public void onLowMemory() {
        super.onLowMemory();
        onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE);
    }

    // Same contract as FlutterActivityAndFragmentDelegate.onTrimMemory: Dart
    // clears caches (image cache) and the renderer trims its textures.
    private static void notifyFlutterMemoryPressure(FlutterEngine engine, int level) {
        if (engine == null)
            return;
        try {
            if (level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) {
                engine.getDartExecutor().notifyLowMemoryWarning();
                engine.getSystemChannel().sendMemoryPressureWarning();
            }
            engine.getRenderer().onTrimMemory(level);
        } catch (Throwable error) {
            android.util.Log.w("InGePerformance", "INGE_FLUTTER_TRIM_FAILED", error);
        }
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

    private void resumeFlutterViewAfterActivityResume(final FlutterView view) {
        // Run after Android has reattached the window. This gives Flutter's
        // SurfaceView a valid Surface before the first resumed frame is asked
        // for, which is essential on low-end devices after a HOT return.
        view.post(() -> {
            if (!activityResumed)
                return;
            if (view == homeView && homeRequested) {
                presentFlutterView(view);
                if (homeChannel != null)
                    homeChannel.invokeMethod("hostVisibility", true);
                android.util.Log.i("InGeGraphics",
                        "INGE_ACTIVITY_SURFACE_REPRESENTED target=home");
            } else if (view == earthView && earthRequested) {
                presentFlutterView(view);
                if (earthChannel != null)
                    earthChannel.invokeMethod("hostVisibility", true);
                android.util.Log.i("InGeGraphics",
                        "INGE_ACTIVITY_SURFACE_REPRESENTED target=earth");
            }
        });
    }

    private void pauseFlutterViewForActivity(FlutterView view, boolean requested) {
        if (view == null || !requested)
            return;
        if (view == homeView && homeRendererActive) {
            if (homeChannel != null)
                homeChannel.invokeMethod("hostVisibility", false);
            if (homeEngine != null)
                homeEngine.getLifecycleChannel().appIsPaused();
            homeRendererActive = false;
        } else if (view == earthView && earthRendererActive) {
            if (earthChannel != null)
                earthChannel.invokeMethod("hostVisibility", false);
            if (earthEngine != null)
                earthEngine.getLifecycleChannel().appIsPaused();
            earthRendererActive = false;
        }
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
    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private void parkFlutterView(FlutterView view) {
        if (view == null)
            return;
        if (view == homeView) {
            if (homeRendererActive) {
                if (homeChannel != null)
                    homeChannel.invokeMethod("hostVisibility", false);
                if (homeEngine != null)
                    homeEngine.getLifecycleChannel().appIsPaused();
                homeRendererActive = false;
                android.util.Log.i("InGeGraphics", "INGE_HOME_RENDERER_SUSPENDED");
            }
        } else if (view == earthView) {
            if (earthRendererActive) {
                if (earthChannel != null)
                    earthChannel.invokeMethod("hostVisibility", false);
                if (earthEngine != null)
                    earthEngine.getLifecycleChannel().appIsPaused();
                earthRendererActive = false;
                android.util.Log.i("InGeGraphics", "INGE_EARTH_RENDERER_SUSPENDED");
            }
        }
        view.setTranslationX(0.0f);
        view.setEnabled(false);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
        fadeOutSurface(view, () -> {
            view.setVisibility(View.GONE);
            view.setAlpha(0.0f);
        });
    }

    // Transición entre superficies (Qt / FlutterView compartida / Earth).
    // Solo alpha de la View (compuesta por el RenderThread de Android).
    private static final long SURFACE_FADE_IN_MS = 200L;
    private static final long SURFACE_FADE_OUT_MS = 120L;

    private void fadeInSurface(View view, boolean wasShown) {
        if (view == null)
            return;
        view.animate().cancel();
        final float from = wasShown ? view.getAlpha() : 0.0f;
        if (from >= 0.99f) {
            view.setAlpha(1.0f);
            return;
        }
        view.setAlpha(from);
        view.animate()
                .alpha(1.0f)
                .setDuration(Math.max(60L, (long) (SURFACE_FADE_IN_MS * (1.0f - from))))
                .setInterpolator(new android.view.animation.DecelerateInterpolator(1.5f))
                .start();
    }

    private void fadeOutSurface(View view, Runnable onHidden) {
        if (view == null)
            return;
        view.animate().cancel();
        if (view.getVisibility() != View.VISIBLE || view.getAlpha() <= 0.01f) {
            onHidden.run();
            return;
        }
        // Si otra orden la vuelve a presentar, cancel() evita el GONE diferido.
        view.animate()
                .alpha(0.0f)
                .setDuration(SURFACE_FADE_OUT_MS)
                .setInterpolator(new android.view.animation.AccelerateInterpolator(1.2f))
                .withEndAction(onHidden)
                .start();
    }

    private void presentFlutterView(FlutterView view) {
        if (view == null)
            return;
        if (view == homeView && homeEngine != null) {
            if (!homeViewAttached) {
                homeView.attachToFlutterEngine(homeEngine);
                homeViewAttached = true;
            }
            if (!homeRendererActive) {
                homeEngine.getLifecycleChannel().appIsResumed();
                homeRendererActive = true;
                android.util.Log.i("InGeGraphics", "INGE_HOME_RENDERER_RESUMED");
            }
        } else if (view == earthView && earthEngine != null) {
            if (!earthViewAttached) {
                earthView.attachToFlutterEngine(earthEngine);
                earthViewAttached = true;
            }
            if (!earthRendererActive) {
                earthEngine.getLifecycleChannel().appIsResumed();
                earthRendererActive = true;
                android.util.Log.i("InGeGraphics", "INGE_EARTH_RENDERER_RESUMED");
            }
        }
        final boolean wasShown = view.getVisibility() == View.VISIBLE;
        view.setTranslationX(0.0f);
        view.setEnabled(true);
        view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_AUTO);
        view.setVisibility(View.VISIBLE);
        fadeInSurface(view, wasShown);
        view.bringToFront();
        view.requestLayout();
        view.invalidate();
    }

    private void destroyHomeFlutter(String reason) {

        final FlutterView view = homeView;

        final MethodChannel channel = homeChannel;
        final MethodChannel renditionChannel = renditionsChannel;

        final FlutterEngine engine = homeEngine;



        homeView = null;

        homeChannel = null;
        renditionsChannel = null;

        homeEngine = null;

        homeReady = false;

        homeViewAttached = false;

        homeRendererActive = false;

        lastSentHomeStateSignature = null;

        if (renditionChannel != null) {
            try { renditionChannel.setMethodCallHandler(null); } catch (Throwable ignored) {}
        }



        // No enviar hostVisibility(false) justo antes de destroy().

        // LifecycleChannel pausa el engine y evitamos una respuesta Dart

        // tardia contra un FlutterJNI ya destruido.

        if (engine != null) {

            try { engine.getLifecycleChannel().appIsPaused(); } catch (Throwable ignored) {}

            try { engine.getActivityControlSurface().detachFromActivity(); } catch (Throwable ignored) {}

        }



        destroyFlutterSurface(view, channel, engine);



        if (view != null || engine != null)

            android.util.Log.i("InGeGraphics",

                    "INGE_HOME_ENGINE_RELEASED reason=" + reason);

    }

    private void destroyEarthFlutter(String reason) {

        locationHandler.removeCallbacks(locationPoll);
        locationHandler.removeCallbacks(locationRefinePoll);



        final FlutterView view = earthView;

        final MethodChannel channel = earthChannel;

        final FlutterEngine engine = earthEngine;



        earthView = null;

        earthChannel = null;

        earthEngine = null;

        earthReady = false;

        earthViewAttached = false;

        earthRendererActive = false;

        pendingImportResult = null;

        pendingExportResult = null;

        pendingExportKml = null;



        // Igual que Home: no generar un platform message inmediatamente

        // antes de destruir el FlutterEngine.

        if (engine != null) {

            try { engine.getLifecycleChannel().appIsPaused(); } catch (Throwable ignored) {}

            try { engine.getActivityControlSurface().detachFromActivity(); } catch (Throwable ignored) {}

        }



        destroyFlutterSurface(view, channel, engine);



        if (view != null || engine != null)

            android.util.Log.i("InGeGraphics",

                    "INGE_EARTH_ENGINE_RELEASED reason=" + reason);

    }

    private void applyFlutterHomeVisibility(boolean visible) {
        if (!visible) {
            parkFlutterView(homeView);
            return;
        }
        final boolean completingEarthBack = earthBackTransitionInProgress;
        if (completingEarthBack)
            hideDirectEarthWebView(false);
        else {
            earthRequested = false;
            hideDirectEarthWebView();
        }
        parkFlutterView(earthView);
        if (earthEngine != null)
            destroyEarthFlutter("switch_to_home");
        try {
            ensureFlutterHome();
            configureHomeViewInsets();
            if (homeView != null && homeReady && homeRequested)
                presentFlutterView(homeView);
            if (homeChannel != null) {
                homeChannel.invokeMethod("hostVisibility", true);
                sendHomeSurfaceState();
            }
            completeEarthBackTransitionIfHomePresented();
        } catch (Throwable error) {
            homeReady = false;
            homeRequested = false;
            destroyHomeFlutter("init_failed");
            android.util.Log.e("InGeFlutterHome", "Flutter Home init failed", error);
        }
    }

    private void applyDirectEarthVisibility(boolean visible) {
        if (!visible) {
            hideDirectEarthWebView(!earthBackTransitionInProgress);
            return;
        }
        if (earthPickerActive)
            exitEarthPicker();
        performanceHandler.removeCallbacks(releaseHiddenEarthRunnable);
        homeRequested = false;
        parkFlutterView(homeView);
        try {
            if (earthEngine != null)
                destroyEarthFlutter("direct_webview_activation");
            ensureDirectEarthWebView();
            applyContextDockBand(earthWebView);
            earthWebView.onResume();
            final boolean earthWasShown = earthWebView.getVisibility() == View.VISIBLE;
            earthWebView.setVisibility(View.VISIBLE);
            fadeInSurface(earthWebView, earthWasShown);
            earthWebView.setEnabled(true);
            earthWebView.bringToFront();
            earthWebView.requestFocus();
            if (!earthWasShown || mapLoadingActive)
                showMapLoading("earth");
            emitEarthPageVisibility(true);
            deliverPendingEarthFocus();
            android.util.Log.i("InGeEarthDirect",
                    "INGE_EARTH_DIRECT_WEBVIEW_VISIBLE "
                            + "flutterEngineCreated=" + (earthEngine != null)
                            + " flutterSurfaceCreated=" + (earthView != null));
        } catch (Throwable error) {
            earthRequested = false;
            hideDirectEarthWebView();
            android.util.Log.e("InGeEarthDirect",
                    "Direct Android WebView init failed", error);
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

        final WebView webView = new WebView(this) {
            private boolean dockGesture;
            @Override public void draw(Canvas canvas) {
                final int save = canvas.save();
                if (!earthPickerActive)
                    clipNativeDock(canvas, getWidth(), getHeight());
                super.draw(canvas);
                canvas.restoreToCount(save);
            }
            @Override public boolean dispatchTouchEvent(MotionEvent event) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN)
                    dockGesture = !earthPickerActive
                            && dockOwnsTouch(event, getWidth(), getHeight());
                // Latch on DOWN so map gestures crossing the dock are intact.
                return !dockGesture && super.dispatchTouchEvent(event);
            }
        };
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
                if (!earthPickerActive)
                    emitEarthPageVisibility(earthRequested
                            && view.getVisibility() == View.VISIBLE);
                deliverPendingEarthFocus();
                deliverPendingEarthPicker();
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

    private void hideDirectEarthWebView() {
        hideDirectEarthWebView(true);
    }

    private void hideDirectEarthWebView(boolean releaseBackCallback) {
        cancelMapLoading("earth_closed");
        emitEarthPageVisibility(false);
        stopEarthLocationSearch();
        if (earthWebView != null) {
            final WebView hiding = earthWebView;
            hiding.onPause();
            hiding.setEnabled(false);
            fadeOutSurface(hiding, () -> hiding.setVisibility(View.GONE));
            if (isLowMemoryTier()) {
                performanceHandler.removeCallbacks(releaseHiddenEarthRunnable);
                performanceHandler.postDelayed(releaseHiddenEarthRunnable,
                        EARTH_LOW_TIER_RELEASE_MS);
            }
        }
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

    // Frees the Cesium WebGL context, tiles and its renderer only while Earth
    // is not the requested surface; the next open (or onResume) recreates it.
    // During the Back transition earthRequested is still true: retry later.
    private void releaseHiddenEarthWebView(String reason) {
        if (earthWebView == null)
            return;
        if (earthBackTransitionInProgress) {
            performanceHandler.removeCallbacks(releaseHiddenEarthRunnable);
            performanceHandler.postDelayed(releaseHiddenEarthRunnable,
                    EARTH_LOW_TIER_RELEASE_MS);
            return;
        }
        if (earthRequested || earthWebView.getVisibility() == View.VISIBLE
                && earthWebView.isEnabled())
            return;
        android.util.Log.i("InGeEarthDirect",
                "INGE_EARTH_WEBVIEW_RELEASED reason=" + reason);
        destroyDirectEarthWebView();
    }









    private boolean dispatchRenditionsBackToFlutter() {
        if (!homeRequested || !"renditions".equals(homeSurfaceMode)
                || homeEngine == null || homeView == null
                || homeView.getVisibility() != View.VISIBLE)
            return false;
        android.util.Log.i("InGeNavigation", "INGE_BACK_CONTEXT=RENDITIONS");
        android.util.Log.i("InGeNavigation", "INGE_BACK_ACTION=INTERNAL_OR_HOME");
        homeEngine.getNavigationChannel().popRoute();
        android.util.Log.i("InGeNavigation", "INGE_BACK_CONSUMED=YES");
        return true;
    }

    private boolean handleEarthBack() {
        if (earthBackTransitionInProgress) {
            android.util.Log.i("InGeNavigation",
                    "INGE_BACK_RECEIVED source=ANDROID");
            android.util.Log.i("InGeNavigation", "INGE_BACK_CONTEXT=EARTH_TRANSITION");
            android.util.Log.i("InGeNavigation", "INGE_BACK_CONSUMED=YES");
            return true;
        }
        if (!earthRequested || earthWebView == null
                || earthWebView.getVisibility() != View.VISIBLE)
            return false;
        android.util.Log.i("InGeNavigation",
                "INGE_BACK_RECEIVED source=ANDROID");
        android.util.Log.i("InGeNavigation", "INGE_BACK_CONTEXT=EARTH");

        earthBackTransitionInProgress = true;
        earthHomeNavigationRequested = false;
        android.util.Log.i("InGeNavigation", "INGE_BACK_ACTION=RETURN_HOME");
        android.util.Log.i("InGeNavigation", "INGE_BACK_CONSUMED=YES");

        hideDirectEarthWebView(false);
        android.util.Log.i("InGeNavigation",
                "INGE_EARTH_WEBVIEW_HIDDEN reason=BACK");

        boolean bridgeAccepted = false;
        try {
            bridgeAccepted = nativeRequestEarthBackToHome();
        } catch (Throwable error) {
            android.util.Log.e("InGeNavigation",
                    "INGE_EARTH_HOME_BRIDGE_FAILED", error);
        }
        if (!bridgeAccepted) {
            earthBackTransitionInProgress = false;
            earthHomeNavigationRequested = false;
            applyDirectEarthVisibility(true);
            android.util.Log.e("InGeNavigation",
                    "INGE_EARTH_BACK_TO_HOME_ABORTED bridgeAccepted=false");
        }
        return true;
    }

    private void completeEarthBackTransitionIfHomePresented() {
        if (!earthBackTransitionInProgress || !earthHomeNavigationRequested
                || !homeRequested || !homeReady
                || !homeRendererActive || homeView == null
                || homeView.getVisibility() != View.VISIBLE)
            return;
        android.util.Log.i("InGeNavigation",
                "INGE_EARTH_HOME_NAVIGATION_REQUESTED");
        earthRequested = false;
        earthBackTransitionInProgress = false;
        earthHomeNavigationRequested = false;
        android.util.Log.i("InGeNavigation",
                "INGE_EARTH_BACK_TO_HOME_COMPLETE");
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event != null && event.getKeyCode() == KeyEvent.KEYCODE_BACK) {
            if (event.getAction() == KeyEvent.ACTION_UP && !event.isCanceled())
                requestGlobalBack();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    public void onBackPressed() {
        requestGlobalBack();
    }

    private void destroyDirectEarthWebView() {
        final WebView webView = earthWebView;
        earthWebView = null;
        earthAssetLoader = null;
        earthWebViewLoaded = false;
        cancelMapLoading("webview_destroyed");
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
    // dead WebView is unusable. Hidden or backgrounded Earth is released and
    // recreated by the next open or by onResume (earthRequested stays true).
    // Visible foreground Earth is recreated once; a second visible loss within
    // 30 s returns Home through the normal Back bridge instead of looping.
    private void recoverEarthRendererGone(WebView view, boolean crashed) {
        final boolean current = view == earthWebView;
        final boolean wasVisible = current && activityResumed && earthRequested
                && !earthBackTransitionInProgress
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
        if (!wasVisible)
            return;
        if (repeated) {
            earthBackTransitionInProgress = true;
            earthHomeNavigationRequested = false;
            boolean bridgeAccepted = false;
            try {
                bridgeAccepted = nativeRequestEarthBackToHome();
            } catch (Throwable error) {
                android.util.Log.e("InGeNavigation",
                        "INGE_EARTH_HOME_BRIDGE_FAILED", error);
            }
            if (bridgeAccepted)
                return;
            earthBackTransitionInProgress = false;
            earthHomeNavigationRequested = false;
        }
        applyDirectEarthVisibility(true);
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
        public void mapLoading(String state, int session, String mapType, int elapsedMs) {
            if (state == null || !state.matches("[A-Z_]{1,24}"))
                return;
            final String type = mapType != null && mapType.matches("[A-Z_]{1,24}") ? mapType : "DEFAULT";
            runOnUiThread(() -> onMapLoadingEvent(state, session, type, elapsedMs));
        }

        @JavascriptInterface
        public void publishDockBackdrop(String json) {
            if (json == null || json.length() > 65536)
                return;
            try {
                nativeDockBackdrop("earth", json);
            } catch (Throwable ignored) {
            }
        }

        @JavascriptInterface
        public void publishContext(String json) {
            if (json == null || json.length() > 16384)
                return;
            try {
                nativeDockPublish("earth", json);
            } catch (Throwable ignored) {
            }
        }

        @JavascriptInterface
        public void clearContext(String ownerId) {
            if (ownerId == null || ownerId.length() > 64)
                return;
            try {
                nativeDockClear("earth", ownerId);
            } catch (Throwable ignored) {
            }
        }

        @JavascriptInterface
        public void completeContextCommand(String json) {
            if (json == null || json.length() > 512)
                return;
            try {
                nativeDockComplete(json);
            } catch (Throwable ignored) {
            }
        }

        @JavascriptInterface
        public boolean pickerSelected(double latitude, double longitude) {
            if (!earthPickerActive || !Double.isFinite(latitude) || !Double.isFinite(longitude)
                    || latitude < -90.0 || latitude > 90.0
                    || longitude < -180.0 || longitude > 180.0)
                return false;
            try {
                nativeEarthPickerSelected(latitude, longitude);
                return true;
            } catch (Throwable error) {
                android.util.Log.e("InGeEarthPicker", "INGE_EARTH_PICKER_SELECT_FAILED", error);
                return false;
            }
        }

        @JavascriptInterface
        public boolean pickerSnapshot(String mapType, double latitude, double longitude, String dataUrl) {
            if (mapType == null || dataUrl == null || dataUrl.length() > 700_000
                    || !dataUrl.startsWith("data:image/jpeg;base64,")
                    || ("SATELLITE".equals(mapType) && dataUrl.length() < 1024)
                    || !Double.isFinite(latitude) || !Double.isFinite(longitude))
                return false;
            try {
                nativeEarthPickerSnapshot("SATELLITE".equals(mapType) ? "SATELLITE" : "DEFAULT",
                        latitude, longitude, dataUrl);
                return true;
            } catch (Throwable error) {
                android.util.Log.e("InGeEarthPicker", "INGE_EARTH_PICKER_SNAPSHOT_FAILED", error);
                return false;
            }
        }

        @JavascriptInterface
        public void requestLocation() {
            runOnUiThread(() -> startEarthLocationSearch());
        }

        @JavascriptInterface
        public void copyText(String text) {
            if (text == null || text.length() > 256)
                return;
            runOnUiThread(() -> {
                final ClipboardManager clipboard = (ClipboardManager)
                        getSystemService(Context.CLIPBOARD_SERVICE);
                if (clipboard != null)
                    clipboard.setPrimaryClip(
                            ClipData.newPlainText("Coordenadas InGe Earth", text));
            });
        }

        @JavascriptInterface
        public boolean usePointInCalicata(double latitude, double longitude,
                                           double altitude, double accuracy,
                                           String timestamp, String source) {
            if (!Double.isFinite(latitude) || !Double.isFinite(longitude)
                    || latitude < -90.0 || latitude > 90.0
                    || longitude < -180.0 || longitude > 180.0)
                return false;
            final String safeTimestamp = timestamp == null
                    ? "" : timestamp.substring(0, Math.min(64, timestamp.length()));
            final String safeSource = source == null
                    ? "InGe Earth" : source.substring(0, Math.min(80, source.length()));
            try {
                return nativeUseEarthPointInCalicata(latitude, longitude,
                        Double.isFinite(altitude) ? altitude : 0.0,
                        Double.isFinite(accuracy) ? accuracy : -1.0,
                        safeTimestamp, safeSource);
            } catch (Throwable error) {
                android.util.Log.e("InGeEarthDirect",
                        "INGE_EARTH_POINT_TO_CALICATA_FAILED", error);
                return false;
            }
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

    private DartExecutor.DartEntrypoint entrypoint(String functionName) {
        final FlutterInjector injector = FlutterInjector.instance();
        injector.flutterLoader().startInitialization(getApplicationContext());
        injector.flutterLoader().ensureInitializationComplete(getApplicationContext(), null);
        return new DartExecutor.DartEntrypoint(
                injector.flutterLoader().findAppBundlePath(), functionName);
    }

    private void markNavigationStart(String target) {
        final long now = SystemClock.elapsedRealtime();
        homeNavigationStartedMs = now;
        android.util.Log.i("InGeNavigation",
                "HOME_CLICK target=" + target + " timestampMs=" + now);
        final JSONObject context = new JSONObject();
        try { context.put("target", target); } catch (Throwable ignored) {}
        emitBetaDiagnostic("NAVIGATION", "INFO", "NAVIGATION_START",
                null, null, context);
    }

    private void markFirstMeaningfulFrame(String target) {
        final long now = SystemClock.elapsedRealtime();
        final long started = homeNavigationStartedMs;
        if (started <= 0L) return;
        final long elapsed = Math.max(0L, now - started);
        homeNavigationStartedMs = 0L;
        android.util.Log.i("InGeNavigation",
                "SUBAPP_FIRST_FRAME target=" + target
                        + " navigationToFirstFrameMs=" + elapsed);
        final JSONObject metrics = new JSONObject();
        final JSONObject context = new JSONObject();
        try {
            metrics.put("duration_ms", elapsed);
            context.put("target", target);
        } catch (Throwable ignored) {}
        emitBetaDiagnostic("NAVIGATION", elapsed > 1500L ? "WARNING" : "INFO",
                elapsed > 1500L ? "SLOW_NAVIGATION" : "SUBAPP_FIRST_FRAME",
                null, metrics, context);
    }

    private Map<String, Object> homeHostState() {
        final Map<String, Object> state = new HashMap<>();
        state.put("themeMode", homeThemeMode);
        state.put("motionScale", homeMotionScale);
        state.put("glassIntensity", homeGlassIntensity);
        state.put("idleGlass", homeGlassIntensity > 0.0);
        state.put("performanceProfile", homePerformanceProfile);
        state.put("motionProfile", "FLUID_NATIVE_60HZ");
        state.put("surfaceMode", homeSurfaceMode);
        state.put("authState", homeAuthStateJson);
        state.put("biometricAvailable", isBiometricAvailable());
        return state;
    }

    private void sendHomeSurfaceState() {
        if (homeChannel == null || !homeReady)
            return;
        final String signature = homeThemeMode + '\u001f'
                + homeMotionScale + '\u001f'
                + homeGlassIntensity + '\u001f'
                + homePerformanceProfile + '\u001f'
                + homeSurfaceMode + '\u001f'
                + isBiometricAvailable() + '\u001f'
                + homeAuthStateJson;
        if (signature.equals(lastSentHomeStateSignature))
            return;
        lastSentHomeStateSignature = signature;
        homeChannel.invokeMethod("hostState", homeHostState());
    }

    private void configureHomeViewInsets() {
        if (homeView == null)
            return;
        final ViewGroup.LayoutParams rawParams = homeView.getLayoutParams();
        if (!(rawParams instanceof FrameLayout.LayoutParams))
            return;
        final FrameLayout.LayoutParams params = (FrameLayout.LayoutParams) rawParams;
        // El Header se proyecta dentro del Stack Flutter. La franja inferior
        // la decide el dock global del host (setContextDockBand).
        final int targetTop = 0;
        final int targetBottom = contextDockBandPx;
        if (params.topMargin == targetTop && params.bottomMargin == targetBottom)
            return;
        params.topMargin = targetTop;
        params.bottomMargin = targetBottom;
        homeView.setLayoutParams(params);
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

    private void authenticateBiometric(MethodChannel.Result result) {
        if (!isBiometricAvailable()) {
            result.success(false);
            return;
        }
        if (pendingBiometricResult != null) {
            result.error("biometric_busy", "Ya hay una verificacion en curso.", null);
            return;
        }
        pendingBiometricResult = result;
        try {
            startActivityForResult(
                    new Intent(this, InGeBiometricActivity.class),
                    BIOMETRIC_AUTH_REQUEST);
        } catch (Throwable error) {
            pendingBiometricResult = null;
            result.error("biometric_unavailable", "No se pudo abrir BiometricPrompt.", null);
        }
    }

    private void ensureFlutterHome() {
        if (homeEngine != null)
            return;
        homeEngine = new FlutterEngine(this, (String[]) null, false);
        // Registro explícito en el engine persistente real: secure_storage,
        // WebView y el plugin InGe quedan disponibles sin instancias paralelas.
        // local_auth se ejecuta en InGeBiometricActivity porque exige FragmentActivity.
        GeneratedPluginRegistrant.registerWith(homeEngine);
        homeEngine.getActivityControlSurface().attachToActivity(this, flutterLifecycle);
        homeChannel = new MethodChannel(
                homeEngine.getDartExecutor().getBinaryMessenger(), HOME_CHANNEL);
        renditionsChannel = new MethodChannel(
                homeEngine.getDartExecutor().getBinaryMessenger(), RENDITIONS_CHANNEL);
        renditionsChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "submit":
                    if (!(call.arguments instanceof String)) {
                        result.error("invalid_rendition_command",
                                "Solicitud de rendiciones inválida.", null);
                        break;
                    }
                    nativeSubmitRenditionCommand((String) call.arguments);
                    result.success(null);
                    break;
                case "pickAttachment":
                    openRenditionAttachment(result);
                    break;
                case "analyzeReceipt":
                    RenditionReceiptOcr.analyze(this, call.arguments, result);
                    break;
                case "openUri":
                    result.success(openExternalUri(call.arguments));
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        });
        dockChannel = new MethodChannel(
                homeEngine.getDartExecutor().getBinaryMessenger(), DOCK_CHANNEL);
        dockChannel.setMethodCallHandler((call, result) -> {
            final Object args = call.arguments;
            try {
                switch (call.method) {
                    case "publish":
                        if (args instanceof String && ((String) args).length() <= 16384)
                            nativeDockPublish("flutter", (String) args);
                        break;
                    case "clear":
                        if (args instanceof String)
                            nativeDockClear("flutter", (String) args);
                        break;
                    case "complete":
                        if (args instanceof String)
                            nativeDockComplete((String) args);
                        break;
                    case "backdrop":
                        if (args instanceof String && ((String) args).length() <= 65536)
                            nativeDockBackdrop("flutter", (String) args);
                        break;
                    default:
                        result.notImplemented();
                        return;
                }
            } catch (Throwable ignored) {
            }
            result.success(null);
        });
        homeChannel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "getHostTokens":
                case "getHostState": {
                    result.success(homeHostState());
                    break;
                }
                case "ready":
                    homeReady = true;
                    if ("auth".equals(homeSurfaceMode))
                        android.util.Log.i("InGeFlutterAuth", "AUTH_FLUTTER_ENGINE_READY");
                    if (homeRequested && homeView != null) {
                        configureHomeViewInsets();
                        presentFlutterView(homeView);
                        homeChannel.invokeMethod("hostVisibility", true);
                    }
                    completeEarthBackTransitionIfHomePresented();
                    result.success(null);
                    sendHomeSurfaceState();
                    break;
                case "firstMeaningfulFrame":
                    markFirstMeaningfulFrame(call.arguments == null
                            ? homeSurfaceMode : call.arguments.toString());
                    result.success(null);
                    break;
                case "recordDiagnostic":
                    if (call.arguments instanceof Map) {
                        try {
                            nativeRecordBetaDiagnostic(
                                    new JSONObject((Map<?, ?>) call.arguments).toString());
                        } catch (Throwable ignored) {
                        }
                    }
                    result.success(null);
                    break;
                case "navigate":
                case "quickAction":
                    postFlutterHomeAction(call.argument("action"));
                    result.success(null);
                    break;
                case "authRequest":
                    if (!(call.arguments instanceof Map)) {
                        result.error("invalid_auth_request", "Solicitud de autenticacion invalida.", null);
                        break;
                    }
                    // Nunca registrar este JSON: puede contener la contraseña
                    // durante los pocos milisegundos que tarda QML en consumirlo.
                    postFlutterAuthRequest(new JSONObject((Map<?, ?>) call.arguments).toString());
                    result.success(null);
                    break;
                case "authenticateBiometric":
                    authenticateBiometric(result);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        });
        homeEngine.getDartExecutor().executeDartEntrypoint(entrypoint("homeMain"));
        homeEngine.getLifecycleChannel().appIsResumed();
        homeView = new FlutterView(this, new FlutterTextureView(this)) {
            private boolean dockGesture;
            @Override public void draw(Canvas canvas) {
                final int save = canvas.save();
                clipNativeDock(canvas, getWidth(), getHeight());
                super.draw(canvas);
                canvas.restoreToCount(save);
            }
            @Override public boolean dispatchTouchEvent(MotionEvent event) {
                if (event.getActionMasked() == MotionEvent.ACTION_DOWN)
                    dockGesture = dockOwnsTouch(event, getWidth(), getHeight());
                return !dockGesture && super.dispatchTouchEvent(event);
            }
        };
        homeView.setBackgroundColor(Color.TRANSPARENT);
        homeView.setVisibility(View.INVISIBLE);
        homeView.attachToFlutterEngine(homeEngine);
        homeViewAttached = true;
        addFlutterView(homeView, 0, 0);
        if ("auth".equals(homeSurfaceMode))
            android.util.Log.i("InGeFlutterAuth", "AUTH_FLUTTER_VIEW_ATTACHED");
    }

    private void openRenditionAttachment(MethodChannel.Result result) {
        if (pendingRenditionAttachmentResult != null) {
            result.error("attachment_busy", "Ya existe una selección pendiente.", null);
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

    private void addFlutterView(FlutterView view, int topDp, int bottomDp) {
        final FrameLayout content = findViewById(android.R.id.content);
        final FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
                Gravity.TOP | Gravity.START);
        params.topMargin = dp(topDp);
        params.bottomMargin = dp(bottomDp);
        content.addView(view, params);
        view.post(() -> applyPreferredFrameRateToSurfaces(
                getWindow().getDecorView()));
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
        if (earthChannel != null)
            earthChannel.invokeMethod("locationStatus", payload);
        emitEarthUiJavascript("receiveNativeLocationStatus", payload);
    }

    private void emitLocationFix(Map<String, Object> fix) {
        if (earthChannel != null)
            earthChannel.invokeMethod("locationFix", new HashMap<>(fix));
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

    private void emitEarthPageVisibility(boolean visible) {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded)
            return;
        webView.post(() -> webView.evaluateJavascript(
                "window.InGeEarthSetVisible&&window.InGeEarthSetVisible("
                        + (visible ? "true" : "false") + ");", null));
    }

    private void deliverPendingEarthFocus() {
        final WebView webView = earthWebView;
        if (webView == null || !earthWebViewLoaded
                || webView.getVisibility() != View.VISIBLE
                || pendingEarthFocusJson.isEmpty())
            return;
        final String json = pendingEarthFocusJson;
        pendingEarthFocusJson = "";
        webView.post(() -> webView.evaluateJavascript(
                "window.InGeEarthUi&&window.InGeEarthUi.focusCoordinate("
                        + json + ");", null));
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
        if (pendingEarthWebImport || pendingImportResult != null) {
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

    private void openEarthDocument(MethodChannel.Result result) {
        if (pendingImportResult != null) {
            result.error("import_busy", "Ya existe una importación pendiente", null);
            return;
        }
        pendingImportResult = result;
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

    private void exportKml(Object arguments, MethodChannel.Result result) {
        if (!(arguments instanceof Map)) {
            result.error("invalid_export", "Faltan datos KML", null);
            return;
        }
        final Map<?, ?> values = (Map<?, ?>) arguments;
        pendingExportKml = String.valueOf(values.get("content"));
        String name = String.valueOf(values.get("name"));
        if (!name.toLowerCase(Locale.ROOT).endsWith(".kml"))
            name += ".kml";
        pendingExportResult = result;
        final Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("application/vnd.google-earth.kml+xml");
        intent.putExtra(Intent.EXTRA_TITLE, name);
        startActivityForResult(intent, EARTH_EXPORT_REQUEST);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (GoogleDriveAuthorization.onActivityResult(this, requestCode, resultCode, data)) return;
        final boolean directEarthActivityResult =
                (requestCode == EARTH_IMPORT_REQUEST && pendingEarthWebImport)
                || (requestCode == EARTH_EXPORT_REQUEST
                    && pendingEarthWebExport);
        if (!directEarthActivityResult && homeEngine != null)
            homeEngine.getActivityControlSurface().onActivityResult(
                    requestCode, resultCode, data);
        if (!directEarthActivityResult && earthEngine != null)
            earthEngine.getActivityControlSurface().onActivityResult(
                    requestCode, resultCode, data);
        if (requestCode == BIOMETRIC_AUTH_REQUEST && pendingBiometricResult != null) {
            final MethodChannel.Result result = pendingBiometricResult;
            pendingBiometricResult = null;
            final boolean authenticated = resultCode == Activity.RESULT_OK
                    && data != null
                    && data.getBooleanExtra(
                            InGeBiometricActivity.EXTRA_AUTHENTICATED, false);
            result.success(authenticated);
            return;
        }
        if (requestCode == RENDITION_ATTACHMENT_REQUEST
                && pendingRenditionAttachmentResult != null) {
            final MethodChannel.Result result = pendingRenditionAttachmentResult;
            if (resultCode != Activity.RESULT_OK || data == null
                    || data.getData() == null) {
                pendingRenditionAttachmentResult = null;
                result.success(null);
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
                        result.success(metadata);
                    });
                } catch (Throwable error) {
                    runOnUiThread(() -> {
                        if (pendingRenditionAttachmentResult != result)
                            return;
                        pendingRenditionAttachmentResult = null;
                        result.error("attachment_copy_failed",
                                error.getMessage(), null);
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
        if (requestCode == EARTH_IMPORT_REQUEST && pendingImportResult != null) {
            final MethodChannel.Result result = pendingImportResult;
            pendingImportResult = null;
            if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
                result.success(null);
                return;
            }
            try {
                result.success(copyEarthDocument(data.getData()));
            } catch (Throwable error) {
                result.error("import_failed", error.getMessage(), null);
            }
            return;
        }
        if (requestCode == EARTH_EXPORT_REQUEST && pendingExportResult != null) {
            final MethodChannel.Result result = pendingExportResult;
            pendingExportResult = null;
            if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
                pendingExportKml = null;
                result.success(false);
                return;
            }
            try (OutputStream output = getContentResolver().openOutputStream(data.getData())) {
                if (output == null)
                    throw new IllegalStateException("No se pudo crear el KML");
                output.write((pendingExportKml == null ? "" : pendingExportKml)
                        .getBytes(StandardCharsets.UTF_8));
                result.success(true);
            } catch (Throwable error) {
                result.error("export_failed", error.getMessage(), null);
            } finally {
                pendingExportKml = null;
            }
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        if (requestCode == InGeAssistantWebHost.MICROPHONE_REQUEST) {
            if (assistantHost != null) assistantHost.finishPermission();
            return;
        }
        // 8104 es propiedad del WebView Earth. Reenviarlo a plugins Flutter
        // sin una solicitud pendiente generaba el aviso de requestCode inválido.
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
        if (homeEngine != null)
            homeEngine.getActivityControlSurface().onRequestPermissionsResult(
                    requestCode, permissions, grantResults);
        if (earthEngine != null)
            earthEngine.getActivityControlSurface().onRequestPermissionsResult(
                    requestCode, permissions, grantResults);
    }

    @Override
    public void onDestroy() {
        if (assistantHost != null) {
            if (assistantHost.isActive()) assistantHost.closeFromUser();
            else assistantHost.close();
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                && globalBackCallback != null) {
            getOnBackInvokedDispatcher().unregisterOnBackInvokedCallback(globalBackCallback);
            globalBackCallback = null;
        }
        emitBetaDiagnostic("LIFECYCLE", "INFO", "ON_DESTROY", null, null, null);
        performanceHandler.removeCallbacks(betaPerformanceSample);
        if (performanceRuntime != null)
            performanceRuntime.setBudgetListener(null);
        performanceHandler.removeCallbacks(releaseHiddenEarthRunnable);
        android.util.Log.i("InGeLifecycle",
                "INGE_ACTIVITY_ON_DESTROY instance=" + System.identityHashCode(this));
        // Relaunch (config/core settings) vs real exit: process-global Qt state is
        // owned by QtActivityBase (retained on relaunch); only Activity-owned
        // surfaces (Flutter/Earth views) are released below.
        android.util.Log.i("InGeLifecycle", "INGE_ACTIVITY_RECREATE changingConfig="
                + isChangingConfigurations() + " finishing=" + isFinishing());
        homeRequested = false;
        earthRequested = false;
        earthBackTransitionInProgress = false;
        earthHomeNavigationRequested = false;
        activityResumed = false;
        if (pendingBiometricResult != null) {
            pendingBiometricResult.success(false);
            pendingBiometricResult = null;
        }
        if (pendingRenditionAttachmentResult != null) {
            pendingRenditionAttachmentResult.success(null);
            pendingRenditionAttachmentResult = null;
        }
        renditionAttachmentExecutor.shutdownNow();
        locationHandler.removeCallbacks(locationPoll);
        locationHandler.removeCallbacks(locationRefinePoll);
        closePendingEarthWebExport();
        pendingEarthWebImport = false;
        destroyDirectEarthWebView();
        destroyHomeFlutter("activity_destroy");
        destroyEarthFlutter("activity_destroy");
        current.clear();
        flutterLifecycle.handleLifecycleEvent(Lifecycle.Event.ON_DESTROY);
        super.onDestroy();
    }

    private void destroyFlutterSurface(FlutterView view, MethodChannel channel,
                                       FlutterEngine engine) {
        if (channel != null) {
            try { channel.setMethodCallHandler(null); } catch (Throwable ignored) {}
        }
        if (view != null) {
            try { view.detachFromFlutterEngine(); } catch (Throwable ignored) {}
            try {
                final Object parent = view.getParent();
                if (parent instanceof ViewGroup)
                    ((ViewGroup) parent).removeView(view);
            } catch (Throwable ignored) {}
        }
        if (engine != null) {
            try { engine.destroy(); } catch (Throwable ignored) {}
        }
    }
}
