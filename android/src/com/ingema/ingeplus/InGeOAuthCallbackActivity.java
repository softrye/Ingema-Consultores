package com.ingema.ingeplus;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

// Receptor del deep link com.ingema.ingeplus://login-callback (Google / Supabase
// OAuth PKCE). La Custom Tab vive encima de InGeQtActivity en la misma tarea: si el
// intent-filter estuviera en InGeQtActivity (singleTop, sin estar arriba) Android
// crearía una segunda instancia de Qt. Esta Activity sin UI entrega la URI a
// InGeQtActivity, cierra la Custom Tab (CLEAR_TOP) y termina.
public final class InGeOAuthCallbackActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        final Intent source = getIntent();
        final Uri data = source != null ? source.getData() : null;
        if (data != null && "com.ingema.ingeplus".equals(data.getScheme())
                && "login-callback".equals(data.getHost()))
            InGeQtActivity.deliverOAuthCallback(data.toString());

        final Intent host = new Intent(this, InGeQtActivity.class);
        host.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        startActivity(host);
        finish();
    }
}
