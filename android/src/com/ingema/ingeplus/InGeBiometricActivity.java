package com.ingema.ingeplus;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.embedding.android.FlutterActivityLaunchConfigs;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * Host acotado de local_auth. QtActivity sigue siendo el unico owner de la
 * aplicacion; FlutterFragmentActivity existe solo durante BiometricPrompt.
 */
public final class InGeBiometricActivity extends FlutterFragmentActivity {
    public static final String EXTRA_AUTHENTICATED = "inge.biometric.authenticated";
    public static final String EXTRA_STATUS = "inge.biometric.status";
    private static final String RESULT_CHANNEL = "inge.biometric/result";

    @Override
    public String getDartEntrypointFunctionName() {
        return "biometricMain";
    }

    @Override
    public FlutterActivityLaunchConfigs.BackgroundMode getBackgroundMode() {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent;
    }

    @Override
    public RenderMode getRenderMode() {
        return RenderMode.texture;
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        // super registra GeneratedPluginRegistrant en este engine real; de ese
        // modo local_auth nunca depende del engine persistente unido a QtActivity.
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), RESULT_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (!"complete".equals(call.method)) {
                        result.notImplemented();
                        return;
                    }
                    boolean authenticated = false;
                    String status = "unavailable";
                    if (call.arguments instanceof Map) {
                        final Map<?, ?> values = (Map<?, ?>) call.arguments;
                        authenticated = Boolean.TRUE.equals(values.get("authenticated"));
                        final Object rawStatus = values.get("status");
                        if (rawStatus != null)
                            status = rawStatus.toString();
                    }
                    final Intent data = new Intent();
                    data.putExtra(EXTRA_AUTHENTICATED, authenticated);
                    data.putExtra(EXTRA_STATUS, status);
                    setResult(Activity.RESULT_OK, data);
                    result.success(null);
                    finish();
                });
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setFinishOnTouchOutside(false);
    }
}
