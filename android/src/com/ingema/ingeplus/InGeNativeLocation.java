package com.ingema.ingeplus;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

import java.util.List;

/**
 * Proveedor nativo de ubicación para InGe+.
 *
 * Mantiene una sola suscripción estable a LocationManager y combina las
 * fuentes fused (Android 12+), GPS y red. QML no crea ni reinicia listeners:
 * PermissionHelper consulta este estado y publica las coordenadas.
 */
public final class InGeNativeLocation implements LocationListener {
    private static final String TAG = "InGeNativeLocation";
    private static final Object LOCK = new Object();
    private static final InGeNativeLocation LISTENER = new InGeNativeLocation();

    private static Context appContext;
    private static LocationManager manager;
    private static boolean running = false;
    private static boolean hasFix = false;
    private static double latitude = Double.NaN;
    private static double longitude = Double.NaN;
    private static double altitude = Double.NaN;
    private static float accuracy = Float.NaN;
    private static long timestampMs = 0L;
    private static long elapsedRealtimeNanos = 0L;
    private static String provider = "";
    private static String status = "idle";
    private static String lastError = "";

    private static final long GPS_INTERVAL_MS = 1000L;
    private static final long NETWORK_INTERVAL_MS = 1800L;
    private static final float MIN_DISTANCE_METERS = 0.25f;
    private static final float MAX_ACCEPTED_ACCURACY_METERS = 1500.0f;
    private static final long MAX_LAST_KNOWN_AGE_MS = 5L * 60L * 1000L;

    private InGeNativeLocation() {}

    public static boolean start(Context context) {
        synchronized (LOCK) {
            if (context == null) {
                status = "no_context";
                lastError = "Contexto Android no disponible";
                return false;
            }

            appContext = context.getApplicationContext();
            if (appContext.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                    != PackageManager.PERMISSION_GRANTED
                    && appContext.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                    != PackageManager.PERMISSION_GRANTED) {
                status = "permission_denied";
                lastError = "Permiso de ubicación no concedido";
                running = false;
                return false;
            }

            manager = (LocationManager) appContext.getSystemService(Context.LOCATION_SERVICE);
            if (manager == null) {
                status = "manager_unavailable";
                lastError = "LocationManager no disponible";
                running = false;
                return false;
            }

            if (!manager.isLocationEnabled()) {
                status = "service_disabled";
                lastError = "La ubicación del dispositivo está desactivada";
                running = false;
                return false;
            }

            if (running) {
                status = hasFix ? "tracking" : "searching";
                return true;
            }

            lastError = "";
            status = "starting";
            seedFromLastKnownLocations();

            boolean registered = false;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                registered |= registerProvider(LocationManager.FUSED_PROVIDER, GPS_INTERVAL_MS);
            }
            registered |= registerProvider(LocationManager.GPS_PROVIDER, GPS_INTERVAL_MS);
            registered |= registerProvider(LocationManager.NETWORK_PROVIDER, NETWORK_INTERVAL_MS);

            running = registered;
            status = registered ? (hasFix ? "tracking" : "searching") : "no_provider";
            if (!registered) {
                lastError = "No hay proveedores de ubicación habilitados";
            }

            Log.i(TAG, "start running=" + running + " hasFix=" + hasFix
                    + " provider=" + provider + " accuracy=" + accuracy);
            return running;
        }
    }

    public static void stop() {
        synchronized (LOCK) {
            if (manager != null) {
                try {
                    manager.removeUpdates(LISTENER);
                } catch (SecurityException | IllegalArgumentException error) {
                    Log.w(TAG, "removeUpdates failed", error);
                }
            }
            running = false;
            status = hasFix ? "paused_with_fix" : "idle";
        }
    }

    public static boolean isRunning() { return running; }
    public static boolean hasFix() { return hasFix; }
    public static double latitude() { return latitude; }
    public static double longitude() { return longitude; }
    public static double altitude() { return altitude; }
    public static double accuracy() { return accuracy; }
    public static long timestampMs() { return timestampMs; }
    public static String provider() { return provider == null ? "" : provider; }
    public static String status() { return status == null ? "" : status; }
    public static String lastError() { return lastError == null ? "" : lastError; }

    private static boolean registerProvider(String providerName, long intervalMs) {
        if (manager == null || providerName == null) {
            return false;
        }
        try {
            if (!manager.getAllProviders().contains(providerName)
                    || !manager.isProviderEnabled(providerName)) {
                return false;
            }
            manager.requestLocationUpdates(providerName,
                    intervalMs,
                    MIN_DISTANCE_METERS,
                    LISTENER,
                    Looper.getMainLooper());
            Log.i(TAG, "Provider registered: " + providerName);
            return true;
        } catch (SecurityException | IllegalArgumentException error) {
            Log.w(TAG, "Provider registration failed: " + providerName, error);
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
            return false;
        }
    }

    private static void seedFromLastKnownLocations() {
        if (manager == null) {
            return;
        }
        try {
            List<String> providers = manager.getProviders(true);
            for (String providerName : providers) {
                Location location = manager.getLastKnownLocation(providerName);
                consider(location, true);
            }
        } catch (SecurityException error) {
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
        }
    }

    private static long ageMs(Location location) {
        if (location == null) {
            return Long.MAX_VALUE;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1
                && location.getElapsedRealtimeNanos() > 0L) {
            long ageNanos = SystemClock.elapsedRealtimeNanos() - location.getElapsedRealtimeNanos();
            return Math.max(0L, ageNanos / 1_000_000L);
        }
        return Math.max(0L, System.currentTimeMillis() - location.getTime());
    }

    private static void consider(Location location, boolean lastKnown) {
        if (location == null) {
            return;
        }

        double lat = location.getLatitude();
        double lon = location.getLongitude();
        float acc = location.hasAccuracy() ? location.getAccuracy() : Float.NaN;
        long age = ageMs(location);

        if (!Double.isFinite(lat) || !Double.isFinite(lon)
                || lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
            return;
        }
        if (!Float.isFinite(acc) || acc <= 0.0f || acc > MAX_ACCEPTED_ACCURACY_METERS) {
            return;
        }
        if (lastKnown && age > MAX_LAST_KNOWN_AGE_MS) {
            return;
        }

        boolean accept = !hasFix;
        if (hasFix) {
            long currentAge = elapsedRealtimeNanos > 0L
                    ? Math.max(0L, (SystemClock.elapsedRealtimeNanos() - elapsedRealtimeNanos) / 1_000_000L)
                    : Long.MAX_VALUE;
            boolean newer = location.getElapsedRealtimeNanos() > elapsedRealtimeNanos;
            boolean substantiallyMoreAccurate = acc + 8.0f < accuracy;
            boolean currentIsStale = currentAge > 12_000L;
            boolean sameProvider = provider != null && provider.equals(location.getProvider());
            boolean notWildlyWorse = acc <= Math.max(accuracy * 2.5f, accuracy + 80.0f);
            accept = substantiallyMoreAccurate
                    || (newer && currentIsStale)
                    || (newer && sameProvider && notWildlyWorse);
        }

        if (!accept) {
            return;
        }

        latitude = lat;
        longitude = lon;
        altitude = location.hasAltitude() ? location.getAltitude() : Double.NaN;
        accuracy = acc;
        timestampMs = location.getTime() > 0L ? location.getTime() : System.currentTimeMillis();
        elapsedRealtimeNanos = location.getElapsedRealtimeNanos();
        provider = location.getProvider() == null ? "unknown" : location.getProvider();
        hasFix = true;
        status = "tracking";
        lastError = "";

        Log.i(TAG, "Location accepted provider=" + provider
                + " accuracy=" + accuracy + " ageMs=" + age);
    }

    @Override
    public void onLocationChanged(Location location) {
        synchronized (LOCK) {
            consider(location, false);
        }
    }

    @Override
    public void onProviderEnabled(String providerName) {
        status = hasFix ? "tracking" : "searching";
    }

    @Override
    public void onProviderDisabled(String providerName) {
        status = hasFix ? "provider_changed" : "searching";
    }

    @Override
    public void onStatusChanged(String providerName, int providerStatus, Bundle extras) {
        // Conservado para compatibilidad con dispositivos Android antiguos.
    }
}
