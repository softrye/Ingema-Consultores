package com.ingema.ingeplus.fusionbridge;

import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Rect;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.view.WindowManager;

/** Local diagnostic FGS in the same APK. No launcher, overlay or saved recording. */
public final class EarthLifecycleController extends Service {
    private static final String CHANNEL = "inge_fusionbridge_probe";
    private static final String STOP = "com.ingema.ingeplus.fusionbridge.STOP";
    private static final int NOTIFICATION = 8195;
    private static EarthLifecycleController current;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private MediaProjection projection;
    private VirtualDisplay display;
    private EarthFrameBridge frames;
    private long session;
    private boolean started;
    private final Runnable timeout = () -> finish("PROBE_TIME_LIMIT_60S");
    private final MediaProjection.Callback callback = new MediaProjection.Callback() {
        @Override public void onStop() { finish("PROJECTION_REVOKED"); }
        @Override public void onCapturedContentVisibilityChanged(boolean visible) {
            if (frames != null) frames.sourceVisibility(visible);
        }
        @Override public void onCapturedContentResize(int width, int height) {
            if (display != null && frames != null) resize(width, height);
        }
    };

    @Override public void onCreate() {
        super.onCreate();
        current = this;
    }
    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null || STOP.equals(intent.getAction())) {
            finish("USER_STOP_OR_EMPTY_RESTART");
            return START_NOT_STICKY;
        }
        long requested = intent.getLongExtra("session", 0);
        if (!FusionBridgeNative.isCurrent(requested) || Build.VERSION.SDK_INT < 34) {
            stopSelf();
            return START_NOT_STICKY;
        }
        // One token / one createVirtualDisplay, including Android 14+.
        if (started) return START_NOT_STICKY;
        started = true;
        session = requested;
        try {
            NotificationManager notifications = getSystemService(NotificationManager.class);
            if (notifications == null) throw new IllegalStateException("Notification service unavailable");
            notifications.createNotificationChannel(new NotificationChannel(CHANNEL,
                    "Prueba visual FusionBridge", NotificationManager.IMPORTANCE_LOW));
            Intent stop = new Intent(this, EarthLifecycleController.class).setAction(STOP);
            PendingIntent stopIntent = PendingIntent.getService(this, 0, stop,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification notification = new Notification.Builder(this, CHANNEL)
                    .setSmallIcon(android.R.drawable.ic_menu_view)
                    .setContentTitle("InGe+ · prueba visual")
                    .setContentText("Captura diagnóstica local · termina en 60 segundos")
                    .setOngoing(true)
                    .addAction(new Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel,
                            "Detener", stopIntent).build())
                    .build();
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
            Intent consent = intent.getParcelableExtra("consent", Intent.class);
            MediaProjectionManager manager = getSystemService(MediaProjectionManager.class);
            if (consent == null || manager == null) throw new IllegalStateException("Consent missing");
            projection = manager.getMediaProjection(intent.getIntExtra("resultCode", Activity.RESULT_CANCELED), consent);
            if (projection == null) throw new IllegalStateException("Projection missing");
            projection.registerCallback(callback, ui);
            frames = new EarthFrameBridge(session, ui, this::finish);
            WindowManager windows = getSystemService(WindowManager.class);
            if (windows == null) throw new IllegalStateException("Window manager missing");
            Rect bounds = windows.getMaximumWindowMetrics().getBounds();
            int[] size = boundedSize(bounds.width(), bounds.height());
            ImageReader reader = frames.createReader(size[0], size[1]);
            frames.adopt(reader);
            display = projection.createVirtualDisplay("InGeFusionBridgeProbe", size[0], size[1],
                    getResources().getConfiguration().densityDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, reader.getSurface(), null, ui);
            if (display == null) throw new IllegalStateException("Virtual display missing");
            FusionBridgeDiagnostics.state("PROBE_WAITING_FRAME", "SOURCE_IDENTITY_UNVERIFIED");
            ui.postDelayed(timeout, 60_000);
        } catch (RuntimeException error) {
            finish("PROBE_ERROR_" + error.getClass().getSimpleName());
        }
        return START_NOT_STICKY;
    }
    private static int[] boundedSize(int width, int height) {
        if (width <= 0 || height <= 0) throw new IllegalArgumentException("Invalid dimensions");
        double scale = Math.min(1.0, 640.0 / Math.max(width, height));
        return new int[] { Math.max(1, (int) Math.round(width * scale)),
                Math.max(1, (int) Math.round(height * scale)) };
    }
    private void resize(int width, int height) {
        try {
            int[] size = boundedSize(width, height);
            ImageReader next = frames.createReader(size[0], size[1]);
            try {
                display.resize(size[0], size[1], getResources().getConfiguration().densityDpi);
                display.setSurface(next.getSurface());
                frames.adopt(next);
            } catch (RuntimeException error) {
                next.close();
                throw error;
            }
        } catch (RuntimeException error) { finish("PROBE_RESIZE_ERROR"); }
    }
    static void hostVisibilityChanged(boolean visible) {
        if (current != null && current.frames != null) current.frames.hostVisibility();
    }
    static void stopCurrent() {
        if (current != null) current.finish("MODULE_STOPPED");
    }
    private void finish(String reason) {
        boolean released = release();
        if (FusionBridgeNative.isCurrent(session))
            FusionBridgeDiagnostics.state("BLOCKED", released ? reason : "RESOURCE_RELEASE_ERROR");
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }
    private boolean release() {
        ui.removeCallbacks(timeout);
        boolean released = true;
        // Detach producer before closing its consumer Surface.
        VirtualDisplay oldDisplay = display;
        display = null;
        if (oldDisplay != null) {
            try { oldDisplay.release(); } catch (RuntimeException error) { released = false; }
        }
        EarthFrameBridge oldFrames = frames;
        frames = null;
        if (oldFrames != null) {
            try { oldFrames.close(); } catch (RuntimeException error) { released = false; }
        }
        MediaProjection old = projection;
        projection = null;
        if (old != null) {
            try { old.unregisterCallback(callback); } catch (RuntimeException error) { released = false; }
            try { old.stop(); } catch (RuntimeException error) { released = false; }
        }
        if (session != 0) FusionBridgeNative.nativeClear(session);
        FusionBridgeNative.probeStopped(session);
        return released;
    }
    @Override public void onDestroy() {
        if (!release() && FusionBridgeNative.isCurrent(session))
            FusionBridgeDiagnostics.state("BLOCKED", "RESOURCE_RELEASE_ERROR");
        if (current == this) current = null;
        super.onDestroy();
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
