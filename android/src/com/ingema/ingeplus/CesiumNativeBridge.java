package com.ingema.ingeplus;

import android.graphics.PixelFormat;
import android.view.SurfaceView;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceResponse;
import androidx.annotation.Keep;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Map;
import java.util.concurrent.Semaphore;

@Keep
public final class CesiumNativeBridge {
    private static final Semaphore assets = new Semaphore(1);
    private static final Map<SurfaceView, Boolean> surfaces = new IdentityHashMap<>();
    private static final Map<View, android.graphics.drawable.Drawable> backgrounds = new IdentityHashMap<>();
    @Keep private static native byte[] nativeAsset(String path);
    @Keep private static native void nativePost(String json);
    @JavascriptInterface public void post(String json) { if (json != null && json.length() <= 32768) nativePost(json); }
    public static void rendererGone() { nativePost("{\"type\":\"error\",\"code\":\"CESIUM_RENDERER_GONE\"}"); }
    public static WebResourceResponse resource(String path) {
        boolean acquired = false;
        try {
            assets.acquire(); acquired = true;
            byte[] bytes = nativeAsset(path);
            if (bytes == null) throw new IllegalStateException();
            boolean failure = bytes.length > 9 && new String(bytes, 0, Math.min(bytes.length, 9), StandardCharsets.UTF_8).startsWith("{\"error\"");
            return new WebResourceResponse(path.endsWith(".json") || failure ? "application/json" : "application/octet-stream", null,
                    failure ? 422 : 200, failure ? "Unprocessable Entity" : "OK", Collections.singletonMap("Cache-Control", path.endsWith("root.json") || failure ? "no-store" : "public,max-age=86400"), new ByteArrayInputStream(bytes));
        } catch (Exception e) {
            return new WebResourceResponse("application/json", "UTF-8", 500, "Internal Error", Collections.emptyMap(), new ByteArrayInputStream("{\"error\":\"CESIUM_NATIVE_ASSET_FAILED\"}".getBytes(StandardCharsets.UTF_8)));
        } finally { if (acquired) assets.release(); }
    }
    // Scoped to the existing Qt surface. No second Qt window or duplicate Dock.
    public static void compose(View view, boolean enabled) {
        if (enabled && view instanceof ViewGroup && view.getClass().getName().endsWith(".QtLayout")) {
            if (!backgrounds.containsKey(view)) backgrounds.put(view, view.getBackground());
            view.setBackgroundColor(android.graphics.Color.TRANSPARENT);
        }
        if (view instanceof SurfaceView && view.getClass().getName().startsWith("org.qtproject.qt.android.")) {
            SurfaceView surface = (SurfaceView) view;
            if (enabled) {
                // The main Qt SurfaceView normally sits below the window. Android
                // has no public getter for this flag; do not use hidden SDK APIs.
                if (!surfaces.containsKey(surface)) surfaces.put(surface, false);
                surface.getHolder().setFormat(PixelFormat.TRANSLUCENT); surface.setZOrderOnTop(true);
            } else if (surfaces.containsKey(surface)) {
                surface.setZOrderOnTop(Boolean.TRUE.equals(surfaces.remove(surface))); surface.getHolder().setFormat(PixelFormat.OPAQUE);
            }
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); ++i) compose(group.getChildAt(i), enabled);
        }
    }
    public static void restoreAll() {
        for (Map.Entry<SurfaceView, Boolean> entry : surfaces.entrySet()) {
            entry.getKey().setZOrderOnTop(Boolean.TRUE.equals(entry.getValue()));
            entry.getKey().getHolder().setFormat(PixelFormat.OPAQUE);
        }
        surfaces.clear();
        for (Map.Entry<View, android.graphics.drawable.Drawable> entry : backgrounds.entrySet()) entry.getKey().setBackground(entry.getValue());
        backgrounds.clear();
    }
}
