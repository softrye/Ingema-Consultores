package com.ingema.ingeplus;

import android.app.Activity;
import android.os.CancellationSignal;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException;
import androidx.credentials.exceptions.NoCredentialException;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;

/** System account selector. No browser, token storage, email lookup or Drive authorization. */
@androidx.annotation.Keep
public final class GoogleNativeSignIn {
    // Public web client ID (audience verified by Supabase), not a secret or Android client ID.
    private static final String SERVER_CLIENT_ID =
        "1012914960220-5jvgaqbths1kbnmkq4cqnm7l9gnhuv01.apps.googleusercontent.com";
    private static long pendingRequest;
    private static CancellationSignal cancellation;

    private GoogleNativeSignIn() {}
    private static native void nativeResult(long request, String token, String error);

    public static void signIn(Activity activity, long request, String nonceHash) {
        if (activity == null) {
            nativeResult(request, "", "GOOGLE_UNAVAILABLE");
            return;
        }
        activity.runOnUiThread(() -> {
            if (pendingRequest != 0) cancel(pendingRequest);
            pendingRequest = request;
            cancellation = new CancellationSignal();
            try {
                GetSignInWithGoogleOption option = new GetSignInWithGoogleOption.Builder(SERVER_CLIENT_ID)
                    .setNonce(nonceHash).build();
                GetCredentialRequest credentialRequest = new GetCredentialRequest.Builder()
                    .addCredentialOption(option).build();
                CredentialManager.create(activity).getCredentialAsync(activity, credentialRequest,
                    cancellation, ContextCompat.getMainExecutor(activity),
                    new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                        @Override public void onResult(GetCredentialResponse result) {
                            if (request != pendingRequest) return;
                            Credential credential = result.getCredential();
                            if (!(credential instanceof CustomCredential)
                                || !GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(credential.getType())) {
                                finish(request, "", "GOOGLE_INVALID_CREDENTIAL");
                                return;
                            }
                            try {
                                GoogleIdTokenCredential google = GoogleIdTokenCredential.createFrom(credential.getData());
                                finish(request, google.getIdToken(), "");
                            } catch (Exception invalid) {
                                finish(request, "", "GOOGLE_INVALID_CREDENTIAL");
                            }
                        }
                        @Override public void onError(GetCredentialException error) {
                            String code = error instanceof GetCredentialCancellationException ? "GOOGLE_CANCELLED"
                                : error instanceof NoCredentialException ? "GOOGLE_NO_CREDENTIAL"
                                : error instanceof GetCredentialProviderConfigurationException ? "GOOGLE_CONFIGURATION"
                                : "GOOGLE_AUTH_ERROR";
                            // SDK exception messages can contain account details. Return only a fixed code.
                            finish(request, "", code);
                        }
                    });
            } catch (RuntimeException error) {
                finish(request, "", "GOOGLE_CONFIGURATION");
            }
        });
    }

    // Called on the Android UI thread; request ID protects a newer picker from stale cancellation.
    public static void cancelOnUiThread(Activity activity, long request) {
        if (activity != null) activity.runOnUiThread(() -> cancel(request));
    }

    public static void cancel(long request) {
        if (request != pendingRequest) return;
        pendingRequest = 0;
        CancellationSignal signal = cancellation;
        cancellation = null;
        if (signal != null) signal.cancel();
    }

    private static void finish(long request, String token, String error) {
        if (request != pendingRequest) return;
        pendingRequest = 0;
        cancellation = null;
        nativeResult(request, token, error);
    }
}
