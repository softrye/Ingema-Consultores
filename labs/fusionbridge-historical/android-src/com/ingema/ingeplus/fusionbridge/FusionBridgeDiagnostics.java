package com.ingema.ingeplus.fusionbridge;

import android.util.Log;
import org.json.JSONObject;

/** Fixed codes only in logcat; never frames, coordinates, consent tokens or secrets. */
public final class FusionBridgeDiagnostics {
    private static volatile String state = "CLOSED";
    private static volatile String detail = "";
    private FusionBridgeDiagnostics() {}
    public static void state(String code, String reason) {
        if (code.equals(state) && reason.equals(detail)) return;
        state = code;
        detail = reason;
        Log.i("InGeFusionBridge", "FUSIONBRIDGE_STATE state=" + code + " reason=" + reason);
    }
    public static JSONObject snapshot() {
        JSONObject out = new JSONObject();
        EarthIntegrationDetector.put(out, "state", state);
        EarthIntegrationDetector.put(out, "detail", detail);
        EarthIntegrationDetector.put(out, "interactive", false);
        EarthIntegrationDetector.put(out, "sourceIdentity", "USER_SELECTED_UNVERIFIED");
        return out;
    }
}
