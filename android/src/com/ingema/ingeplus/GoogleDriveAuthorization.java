package com.ingema.ingeplus;

import android.accounts.Account;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.os.Build;
import android.os.Bundle;
import com.google.android.gms.auth.api.identity.AuthorizationRequest;
import com.google.android.gms.auth.api.identity.AuthorizationResult;
import com.google.android.gms.auth.api.identity.ClearTokenRequest;
import com.google.android.gms.auth.api.identity.Identity;
import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.common.api.Scope;
import java.util.Collections;
import java.util.Locale;
import java.security.MessageDigest;

/** Google owns account selection and consent. No token is logged or persisted. */
public final class GoogleDriveAuthorization {
    private static final int REQUEST = 29173;
    private static String pending = "";
    private static boolean cancelled;
    private GoogleDriveAuthorization() {}
    private static native void nativeAuthorized(String request, String token, String picked, String error);

    public static void authorize(Activity activity, String request, String account,
                                 String folder, boolean picker, boolean interactive) {
        activity.runOnUiThread(() -> {
            if (!pending.isEmpty()) {
                nativeAuthorized(request, "", "", "Hay otra autorización Google en curso. Reintenta al cerrarla.");
                return;
            }
            pending = request;
            cancelled = false;
            try {
                AuthorizationRequest.Builder builder = AuthorizationRequest.builder()
                    .setRequestedScopes(Collections.singletonList(new Scope("https://www.googleapis.com/auth/drive.file")))
                    .setOptOutIncludingGrantedScopes(true);
                if (!account.isEmpty()) builder.setAccount(new Account(account, "com.google"));
                if (picker) {
                    builder.setPrompt(AuthorizationRequest.Prompt.CONSENT
                        | (account.isEmpty() ? AuthorizationRequest.Prompt.SELECT_ACCOUNT : 0))
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_OAUTH_TRIGGER, "true")
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_FOLDER_SELECTION, "true")
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_MULTIPLE, "false")
                        .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_MIMETYPES, "application/vnd.google-apps.folder");
                    // Let the user browse/search folders in this Google account.
                    // C++ accepts only the configured destination ID after selection.
                }
                Identity.getAuthorizationClient(activity).authorize(builder.build())
                    .addOnSuccessListener(result -> {
                        if (!request.equals(pending)) return;
                        if (cancelled) { pending = ""; return; }
                        if (result.hasResolution()) {
                            if (!interactive) {
                                finish(request, "", "", "Autoriza Google Drive tocando Reintentar en la exportación.");
                                return;
                            }
                            try {
                                activity.startIntentSenderForResult(result.getPendingIntent().getIntentSender(),
                                    REQUEST, null, 0, 0, 0);
                            } catch (Exception e) { finish(request, "", "", "No se pudo abrir la autorización Google."); }
                        } else deliver(request, result);
                    })
                    .addOnFailureListener(e -> finish(request, "", "", error(activity, e)));
            } catch (Exception e) { finish(request, "", "", error(activity, e)); }
        });
    }
    public static void cancel(Activity activity, String request) {
        activity.runOnUiThread(() -> { if (request.equals(pending)) cancelled = true; });
    }
    public static void invalidateToken(Activity activity, String token) {
        activity.runOnUiThread(() -> {
            try { Identity.getAuthorizationClient(activity)
                .clearToken(ClearTokenRequest.builder().setToken(token).build()); }
            catch (Exception ignored) { /* The original HTTP 401 remains visible. */ }
        });
    }
    public static boolean onActivityResult(Activity activity, int code, int resultCode, Intent data) {
        if (code != REQUEST) return false;
        String request = pending;
        if (request.isEmpty()) return true;
        if (cancelled) { pending = ""; return true; }
        if (data == null) {
            finish(request, "", "", "Google cerró la autorización sin devolver datos (resultado Android "
                + resultCode + "). Verifica el cliente OAuth y la firma SHA-1 del APK.");
            return true;
        }
        try { deliver(request, Identity.getAuthorizationClient(activity).getAuthorizationResultFromIntent(data)); }
        // A RESULT_CANCELED intent can contain an OAuth configuration failure.
        // Let the SDK decode it instead of replacing its status with cancellation.
        catch (Exception e) { finish(request, "", "", error(activity, e)); }
        return true;
    }
    private static void deliver(String request, AuthorizationResult result) {
        Bundle params = result.getTokenResponseParams();
        finish(request, result.getAccessToken(), params == null ? "" : params.getString("picked_file_ids", ""), "");
    }
    private static void finish(String request, String token, String picked, String error) {
        if (!request.equals(pending)) return;
        boolean ignore = cancelled;
        pending = "";
        if (!ignore) nativeAuthorized(request, token == null ? "" : token, picked, error);
    }
    public static String signingIdentity(Activity activity) {
        try {
            String name = activity.getPackageName();
            PackageManager manager = activity.getPackageManager();
            Signature[] signatures;
            if (Build.VERSION.SDK_INT >= 28) {
                PackageInfo info = manager.getPackageInfo(name, PackageManager.GET_SIGNING_CERTIFICATES);
                signatures = info.signingInfo.getApkContentsSigners();
            } else signatures = manager.getPackageInfo(name, PackageManager.GET_SIGNATURES).signatures;
            if (signatures == null || signatures.length != 1) return "";
            byte[] digest = MessageDigest.getInstance("SHA-1").digest(signatures[0].toByteArray());
            StringBuilder hash = new StringBuilder();
            for (byte value : digest) {
                if (hash.length() > 0) hash.append(':');
                hash.append(String.format(Locale.ROOT, "%02X", value & 0xff));
            }
            return name + "|" + hash;
        } catch (Exception ignored) { return ""; }
    }
    private static String error(Activity activity, Exception e) {
        if (e instanceof ApiException) {
            int code = ((ApiException)e).getStatusCode();
            if (code == 10) {
                String identity = signingIdentity(activity);
                return "Google OAuth: configuración de la app rechazada (código 10)."
                    + (identity.isEmpty() ? "" : "\nPaquete y SHA-1 de este APK: " + identity.replace('|', '\n'))
                    + "\nRegistra esta firma en un cliente OAuth Android del proyecto ingeplus-drive. Cambiar de correo no corrige la firma.";
            }
            if (code == 16) return "Google interrumpió la autorización (código 16). Completa el consentimiento y la selección de carpeta al reintentar.";
            return "No se pudo autorizar Google Drive (código " + code + "). Verifica usuarios de prueba y Google Picker API.";
        }
        return "No se pudo autorizar Google Drive. Verifica conexión y Google Play Services.";
    }
}
