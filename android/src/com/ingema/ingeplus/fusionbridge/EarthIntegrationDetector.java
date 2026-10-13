package com.ingema.ingeplus.fusionbridge;

import android.content.Context;
import android.content.Intent;
import android.content.pm.ComponentInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Uses public PackageManager APIs only; exported is not proof of an IPC contract. */
public final class EarthIntegrationDetector {
    public static final String EARTH_PACKAGE = "com.google.earth";
    private EarthIntegrationDetector() {}

    @SuppressWarnings("deprecation")
    public static JSONObject inspect(Context context) {
        JSONObject result = new JSONObject();
        try {
            result.put("androidApi", Build.VERSION.SDK_INT);
            result.put("projectionProbeSupported", Build.VERSION.SDK_INT >= 34);
            result.put("directContract", "UNVERIFIED");
            result.put("interactive", false);
            PackageManager pm = context.getPackageManager();
            int flags = PackageManager.GET_ACTIVITIES | PackageManager.GET_SERVICES
                    | PackageManager.GET_PROVIDERS | PackageManager.GET_META_DATA;
            PackageInfo info = pm.getPackageInfo(EARTH_PACKAGE, flags);
            result.put("installed", true);
            result.put("enabled", info.applicationInfo != null && info.applicationInfo.enabled);
            result.put("version", info.versionName == null ? "" : info.versionName);
            Intent launch = pm.getLaunchIntentForPackage(EARTH_PACKAGE);
            result.put("launchable", launch != null);
            result.put("launchActivity", launch != null && launch.getComponent() != null
                    ? launch.getComponent().getClassName() : "");
            JSONArray components = new JSONArray();
            inventory(components, "activity", info.activities);
            inventory(components, "service", info.services);
            inventory(components, "provider", info.providers);
            result.put("exportedComponents", components);
            result.put("blocker", "EARTH_COOPERATION_UNVERIFIED");
        } catch (PackageManager.NameNotFoundException missing) {
            put(result, "installed", false);
            put(result, "blocker", "EARTH_NOT_INSTALLED_OR_NOT_VISIBLE");
        } catch (RuntimeException error) {
            put(result, "installed", false);
            put(result, "blocker", "EARTH_DETECTION_ERROR_" + error.getClass().getSimpleName());
        } catch (JSONException error) {
            put(result, "blocker", "EARTH_DIAGNOSTIC_ENCODING_ERROR");
        }
        return result;
    }
    private static void inventory(JSONArray out, String kind, ComponentInfo[] entries)
            throws JSONException {
        if (entries == null) return;
        for (ComponentInfo entry : entries) {
            if (!entry.exported || !entry.enabled) continue;
            JSONObject component = new JSONObject();
            component.put("kind", kind);
            component.put("name", entry.name);
            // No private manifest parsing, hidden API, guessed Binder action or token.
            out.put(component);
        }
    }
    static void put(JSONObject out, String key, Object value) {
        try { out.put(key, value); }
        catch (JSONException error) { throw new IllegalStateException("Diagnostic encoding", error); }
    }
}
