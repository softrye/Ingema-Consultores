package com.ingema.ingeplus.fusionbridge;

import android.app.Activity;
import android.content.Intent;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.WindowManager;
import com.ingema.ingeplus.InGeQtActivity;
import org.json.JSONObject;
import java.lang.ref.WeakReference;

/** JNI entry point, owned by the single Qt Activity. All mutations run on UI thread. */
public final class FusionBridgeNative {
    private static final int CONSENT_REQUEST = 8194;
    private static final Handler UI = new Handler(Looper.getMainLooper());
    private static volatile long wantedSession;
    private static long consentSession;
    private static long probeUsedSession;
    private static long secureSession;
    private static boolean secureAdded;
    private static WeakReference<Activity> secureHost = new WeakReference<>(null);
    private static volatile boolean hostResumed;
    private static volatile boolean hostSessionLost;
    private static volatile JSONObject detection = new JSONObject();
    private FusionBridgeNative() {}

    public static native void nativeFrame(long generation, byte[] rgba, int width, int height);
    public static native void nativeClear(long generation);

    public static void open(long generation) {
        UI.post(() -> {
            releaseProbe();
            wantedSession = generation;
            hostSessionLost = false;
            InGeQtActivity host = InGeQtActivity.currentActivity();
            if (host == null || host.isFinishing() || host.isDestroyed()) {
                FusionBridgeDiagnostics.state("BLOCKED", "HOST_UNAVAILABLE");
                return;
            }
            detection = EarthIntegrationDetector.inspect(host);
            FusionBridgeDiagnostics.state("BLOCKED", detection.optString("blocker"));
        });
    }
    public static String snapshotJson() {
        JSONObject out = FusionBridgeDiagnostics.snapshot();
        EarthIntegrationDetector.put(out, "moduleSession", wantedSession);
        EarthIntegrationDetector.put(out, "hostSessionLost", hostSessionLost);
        EarthIntegrationDetector.put(out, "hostSessionRecoveryReady", EarthSessionPolicy.shouldRecover(
                wantedSession, hostResumed, hostSessionLost));
        EarthIntegrationDetector.put(out, "detection", detection);
        return out.toString();
    }
    public static void close() {
        UI.post(() -> {
            long old = wantedSession;
            wantedSession = 0;
            hostSessionLost = false;
            if (old != 0) nativeClear(old);
            releaseProbe();
            FusionBridgeDiagnostics.state("CLOSED", "MODULE_CLOSED");
        });
    }
    public static void requestCaptureProbe(long generation) {
        UI.post(() -> {
            if (!isCurrent(generation)) return;
            InGeQtActivity host = InGeQtActivity.currentActivity();
            if (host == null || host.isFinishing() || host.isDestroyed()
                    || !hostResumed || Build.VERSION.SDK_INT < 34) {
                FusionBridgeDiagnostics.state("BLOCKED", "PROBE_REQUIRES_VISIBLE_HOST_API34");
                return;
            }
            if (!detection.optBoolean("installed") || !detection.optBoolean("enabled")) {
                FusionBridgeDiagnostics.state("BLOCKED", "EARTH_NOT_AVAILABLE");
                return;
            }
            if (consentSession != 0) {
                FusionBridgeDiagnostics.state("BLOCKED", "CONSENT_ALREADY_PENDING");
                return;
            }
            if (probeUsedSession == generation) {
                FusionBridgeDiagnostics.state("BLOCKED", "REENTER_MODULE_FOR_NEW_PROBE");
                return;
            }
            releaseProbe();
            // Keep our window protected for the entire capture. Selecting this app
            // or the entire display cannot feed our displayed image back to itself.
            secureHost = new WeakReference<>(host);
            secureSession = generation;
            secureAdded = (host.getWindow().getAttributes().flags
                    & WindowManager.LayoutParams.FLAG_SECURE) == 0;
            host.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
            consentSession = generation;
            try {
                MediaProjectionManager manager = host.getSystemService(MediaProjectionManager.class);
                if (manager == null) throw new IllegalStateException("Projection unavailable");
                host.startActivityForResult(manager.createScreenCaptureIntent(), CONSENT_REQUEST);
                FusionBridgeDiagnostics.state("AWAITING_CONSENT", "SELECT_ONLY_GOOGLE_EARTH");
            } catch (RuntimeException error) {
                consentSession = 0;
                releaseProbe();
                FusionBridgeDiagnostics.state("BLOCKED", "CONSENT_REQUEST_" + error.getClass().getSimpleName());
            }
        });
    }
    public static boolean onActivityResult(Activity host, int requestCode, int resultCode, Intent data) {
        if (requestCode != CONSENT_REQUEST) return false;
        long generation = consentSession;
        consentSession = 0;
        if (!isCurrent(generation) || resultCode != Activity.RESULT_OK || data == null) {
            releaseProbe();
            FusionBridgeDiagnostics.state(wantedSession == 0 ? "CLOSED" : "BLOCKED",
                    "CONSENT_CANCELLED_OR_SESSION_CLOSED");
            return true;
        }
        try {
            probeUsedSession = generation;
            Intent service = new Intent(host, EarthLifecycleController.class);
            service.putExtra("session", generation);
            service.putExtra("resultCode", resultCode);
            service.putExtra("consent", data);
            // Consent first, FGS second, getMediaProjection third (inside service).
            host.startForegroundService(service);
            FusionBridgeDiagnostics.state("PROBE_STARTING", "SOURCE_IDENTITY_UNVERIFIED");
        } catch (RuntimeException error) {
            releaseProbe();
            FusionBridgeDiagnostics.state("BLOCKED", "PROBE_START_" + error.getClass().getSimpleName());
        }
        return true;
    }
    public static void command(String command) {
        UI.post(() -> FusionBridgeDiagnostics.state("BLOCKED", EarthInputController.rejectionFor(command)));
    }
    public static void onHostResume() {
        hostResumed = true;
        EarthLifecycleController.hostVisibilityChanged(true);
    }
    public static void onHostPause() {
        hostResumed = false;
        if (wantedSession != 0) nativeClear(wantedSession);
        EarthLifecycleController.hostVisibilityChanged(false);
    }
    public static void onHostDestroyed() {
        long old = wantedSession;
        // A late permission result may replace diagnostics, never this marker.
        hostSessionLost = hostSessionLost || old != 0;
        wantedSession = 0;
        consentSession = 0;
        hostResumed = false;
        if (old != 0) nativeClear(old);
        releaseProbe();
        FusionBridgeDiagnostics.state("CLOSED", "HOST_DESTROYED");
    }
    static boolean isCurrent(long generation) { return generation != 0 && wantedSession == generation; }
    static boolean hostResumed() { return hostResumed; }
    private static void releaseProbe() {
        EarthLifecycleController.stopCurrent();
        restoreSecureFlag();
    }
    static void restoreSecureFlag() {
        Activity host = secureHost.get();
        if (secureAdded && host != null && !host.isDestroyed())
            host.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
        secureAdded = false;
        secureSession = 0;
        secureHost.clear();
    }
    static void probeStopped(long generation) {
        if (secureSession == generation) restoreSecureFlag();
    }
}
