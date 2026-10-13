package com.ingema.ingeplus.fusionbridge;

import android.graphics.PixelFormat;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.SystemClock;
import java.nio.ByteBuffer;
import java.util.zip.CRC32;

/** Diagnostic pixels only. UI handler owns reader, policy and visibility. */
final class EarthFrameBridge {
    private final long session;
    private final Handler handler;
    private final java.util.function.Consumer<String> onFailure;
    private final EarthFramePolicy policy = new EarthFramePolicy();
    private ImageReader reader;
    private long lastRead = -250;
    private boolean sourceVisible;
    private boolean published;
    private boolean blackFrame;
    private long allowedSince = -1;
    private boolean closed;
    private final Runnable watchdog = new Runnable() {
        @Override public void run() {
            if (closed) return;
            long now = SystemClock.elapsedRealtime();
            if (!policy.fresh(now)) {
                clear();
                if (!blackFrame && allowedSince >= 0 && now - allowedSince >= EarthFramePolicy.STALE_MS)
                    FusionBridgeDiagnostics.state("PROBE_NO_CONTENT_CHANGE", "NO_CHANGED_PIXELS_2500MS");
            }
            handler.postDelayed(this, 250);
        }
    };

    EarthFrameBridge(long generation, Handler ui, java.util.function.Consumer<String> failure) {
        session = generation;
        handler = ui;
        onFailure = failure;
        policy.begin(session);
        handler.postDelayed(watchdog, 250);
    }
    ImageReader createReader(int width, int height) {
        ImageReader next = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2);
        next.setOnImageAvailableListener(this::consume, handler);
        return next;
    }
    void adopt(ImageReader next) {
        ImageReader old = reader;
        reader = next;
        clear();
        policy.setVisible(false);
        policy.setVisible(sourceVisible && FusionBridgeNative.hostResumed());
        allowedSince = sourceVisible && FusionBridgeNative.hostResumed()
                ? SystemClock.elapsedRealtime() : -1;
        if (old != null) old.close();
    }
    void sourceVisibility(boolean value) {
        sourceVisible = value;
        hostVisibility();
        if (!value)
            FusionBridgeDiagnostics.state("PROBE_SOURCE_HIDDEN", "CAPTURED_APP_NOT_VISIBLE");
    }
    void hostVisibility() {
        boolean visible = sourceVisible && FusionBridgeNative.hostResumed();
        policy.setVisible(visible);
        if (!visible) allowedSince = -1;
        else if (allowedSince < 0) allowedSince = SystemClock.elapsedRealtime();
        if (!visible) clear();
    }
    private void consume(ImageReader source) {
        if (closed || source != reader) return;
        try (Image image = source.acquireLatestImage()) {
            if (image == null) return;
            long now = SystemClock.elapsedRealtime();
            if (!FusionBridgeNative.isCurrent(session) || !sourceVisible
                    || !FusionBridgeNative.hostResumed() || now - lastRead < 250) return;
            lastRead = now;
            int width = image.getWidth(), height = image.getHeight();
            Image.Plane plane = image.getPlanes()[0];
            int pixelStride = plane.getPixelStride(), rowStride = plane.getRowStride();
            if (pixelStride < 4) throw new IllegalStateException("Unsupported pixel format");
            ByteBuffer buffer = plane.getBuffer();
            byte[] rgba = new byte[width * height * 4];
            int origin = buffer.position();
            for (int y = 0; y < height; ++y) {
                for (int x = 0; x < width; ++x) {
                    int input = origin + y * rowStride + x * pixelStride;
                    int output = (y * width + x) * 4;
                    rgba[output] = buffer.get(input);
                    rgba[output + 1] = buffer.get(input + 1);
                    rgba[output + 2] = buffer.get(input + 2);
                    rgba[output + 3] = buffer.get(input + 3);
                }
            }
            boolean nonBlack = false;
            for (int i = 0; i < rgba.length; i += 4) {
                if ((rgba[i] & 255) > 8 || (rgba[i + 1] & 255) > 8 || (rgba[i + 2] & 255) > 8) {
                    nonBlack = true;
                    break;
                }
            }
            CRC32 crc = new CRC32();
            crc.update(rgba);
            if (policy.accept(session, now, crc.getValue(), nonBlack)) {
                blackFrame = false;
                FusionBridgeNative.nativeFrame(session, rgba, width, height);
                published = true;
                FusionBridgeDiagnostics.state("PROBE_FRAMES_UNVERIFIED", "PIXEL_CHANGE_NOT_EARTH_IDENTITY");
            } else if (!nonBlack) {
                blackFrame = true;
                clear();
                FusionBridgeDiagnostics.state("PROBE_BLACK_FRAME", "SECURE_OR_EMPTY_CAPTURE");
            }
        } catch (RuntimeException error) {
            clear();
            policy.setVisible(false);
            onFailure.accept("FRAME_READ_" + error.getClass().getSimpleName());
        }
    }
    private void clear() {
        if (!published) return;
        published = false;
        FusionBridgeNative.nativeClear(session);
    }
    void close() {
        if (closed) return;
        closed = true;
        handler.removeCallbacks(watchdog);
        policy.stop();
        clear();
        if (reader != null) { reader.close(); reader = null; }
    }
}
