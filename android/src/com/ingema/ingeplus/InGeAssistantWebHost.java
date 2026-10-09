package com.ingema.ingeplus;

import android.Manifest;
import android.app.Activity;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.webkit.*;
import android.widget.FrameLayout;
import androidx.webkit.WebViewAssetLoader;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

/** Hosts the real Gemini Live console. Only packaged, trusted assets own the bridge. */
final class InGeAssistantWebHost {
    static final int MICROPHONE_REQUEST = 8110;
    private static final String ORIGIN = "https://appassets.androidplatform.net";
    private static final String URL = ORIGIN + "/assets/inge-ai/index.html";
    private final Activity activity;
    private WebView view;
    private PermissionRequest pendingPermission;
    private boolean active;
    private boolean loaded;
    private String visuals = "{}";
    private static native void nativeMessage(String message);

    InGeAssistantWebHost(Activity activity) { this.activity = activity; }
    boolean isActive() { return active; }
    @android.annotation.SuppressLint("SetJavaScriptEnabled")
    void open(String theme) {
        visuals = theme;
        active = true;
        if (view == null) {
            view = new WebView(activity);
            view.setBackgroundColor(Color.TRANSPARENT);
            WebSettings settings = view.getSettings();
            settings.setJavaScriptEnabled(true);
            settings.setAllowFileAccess(false);
            settings.setAllowContentAccess(false);
            settings.setDomStorageEnabled(false);
            settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
            settings.setMediaPlaybackRequiresUserGesture(true);
            final WebViewAssetLoader assets = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(activity)).build();
            view.addJavascriptInterface(new Bridge(), "InGeAssistantNative");
            view.setWebViewClient(new WebViewClient() {
                @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) { return true; }
                @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                    Uri uri = r.getUrl();
                    if (ORIGIN.equals(uri.getScheme() + "://" + uri.getHost()) && uri.getPath().startsWith("/assets/inge-ai/")) {
                        WebResourceResponse local = assets.shouldInterceptRequest(uri);
                        if (local != null) return local;
                    }
                    // WebView subresources never load remote pages/scripts. Live uses its SDK WebSocket.
                    return new WebResourceResponse("text/plain", "UTF-8", 403, "Blocked", java.util.Collections.emptyMap(), new ByteArrayInputStream(new byte[0]));
                }
                @Override public void onPageFinished(WebView v, String url) {
                    if (!URL.equals(url)) return;
                    loaded = true;
                    message("{\"event\":\"visuals\",\"visuals\":" + visuals + "}");
                }
                @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                    if (r.isForMainFrame()) {
                        // Explicit packaging failure, no disguised mock assistant.
                        v.loadData("<p>Faltan los recursos de InGe+ IA. Genera el proyecto web antes de empaquetar Android.</p>", "text/html", "UTF-8");
                    }
                }
                // Without this override Android kills the whole app when the
                // renderer dies (OOM kill or crash). The dead WebView is unusable:
                // close the assistant through the normal path and keep InGe+ alive.
                @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail detail) {
                    final boolean crashed = detail != null && detail.didCrash();
                    android.util.Log.e("InGeAssistant", "INGE_ASSISTANT_RENDERER_GONE crashed=" + crashed);
                    JSONObject context = new JSONObject();
                    try { context.put("active", active); context.put("current", v == view); }
                    catch (org.json.JSONException ignored) {}
                    InGeQtActivity.reportWebViewRendererGone("ASSISTANT", crashed, context);
                    if (v == view) {
                        closeFromUser();
                    } else {
                        android.view.ViewParent parent = v.getParent();
                        if (parent instanceof android.view.ViewGroup) ((android.view.ViewGroup) parent).removeView(v);
                        v.destroy();
                    }
                    return true;
                }
            });
            view.setWebChromeClient(new WebChromeClient() {
                @Override public void onPermissionRequest(PermissionRequest request) {
                    activity.runOnUiThread(() -> {
                        String[] resources = request.getResources();
                        if (!active || !ORIGIN.equals(request.getOrigin().toString().replaceAll("/$", "")) ||
                            resources.length != 1 || !PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(resources[0])) { request.deny(); return; }
                        if (pendingPermission != null) pendingPermission.deny();
                        pendingPermission = request;
                        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) finishPermission();
                        else activity.requestPermissions(new String[]{Manifest.permission.RECORD_AUDIO}, MICROPHONE_REQUEST);
                    });
                }
                @Override public void onPermissionRequestCanceled(PermissionRequest request) {
                    activity.runOnUiThread(() -> { if (pendingPermission == request) pendingPermission = null; });
                }
            });
            FrameLayout content = activity.findViewById(android.R.id.content);
            content.addView(view, new FrameLayout.LayoutParams(-1, -1));
            view.loadUrl(URL);
        }
        view.setVisibility(android.view.View.VISIBLE);
        view.bringToFront(); view.onResume(); view.requestFocus();
        if (loaded) message("{\"event\":\"visuals\",\"visuals\":" + visuals + "}");
    }
    void message(String json) {
        if (active && loaded && view != null)
            view.evaluateJavascript("window.dispatchEvent(new CustomEvent('inge-native',{detail:JSON.parse(" + JSONObject.quote(json) + ")}));", null);
    }
    void finishPermission() {
        PermissionRequest request = pendingPermission; pendingPermission = null;
        if (request == null) return;
        if (active && activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
            request.grant(new String[]{PermissionRequest.RESOURCE_AUDIO_CAPTURE});
        else request.deny();
    }
    void pause() {
        // The runtime permission dialog may temporarily pause this Activity.
        if (pendingPermission == null && active) closeFromUser();
    }
    void close() {
        if (!active && view == null) return;
        active = false;
        if (pendingPermission != null) { pendingPermission.deny(); pendingPermission = null; }
        // Destroying the context guarantees microphone, sockets, audio and transient tokens stop.
        if (view != null) {
            view.removeJavascriptInterface("InGeAssistantNative"); view.stopLoading();
            ((android.view.ViewGroup)view.getParent()).removeView(view);
            view.destroy(); view = null; loaded = false;
        }
    }
    void closeFromUser() { close(); nativeMessage("{\"operation\":\"closed\"}"); }
    private final class Bridge {
        @JavascriptInterface public void postMessage(String json) {
            if (json == null || json.length() > 32000) return;
            activity.runOnUiThread(() -> {
                if (!active || view == null || !URL.equals(view.getUrl())) return;
                try {
                    String operation = new JSONObject(json).optString("operation");
                    if ("closed".equals(operation)) closeFromUser();
                    else if ("chat".equals(operation) || "live-token".equals(operation)) nativeMessage(json);
                } catch (org.json.JSONException ignored) { /* malformed input cannot cross the bridge */ }
            });
        }
    }
}
