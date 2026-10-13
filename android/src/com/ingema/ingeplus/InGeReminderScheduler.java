package com.ingema.ingeplus;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import java.util.Calendar;

/**
 * Recordatorios de actividades pendientes (Home V1, 2026-10-12).
 *
 * Solo se notifica una acción verificable que la app informó en su última
 * ejecución (cambios de calicatas pendientes de sincronizar). Alarma diaria
 * inexacta del sistema: sin proceso permanente ni permiso de alarmas exactas.
 * Máximo una notificación por día y nunca entre 21:00 y 8:00. La pantalla
 * bloqueada muestra una versión pública sin detalles. Al tocarla se abre la
 * app, que exige una sesión autorizada (AuthSession) antes de mostrar datos.
 */
public final class InGeReminderScheduler {
    private static final String PREFS = "inge_reminders";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_PENDING = "pending_count";
    private static final String KEY_LAST_DAY = "last_shown_day";
    private static final String CHANNEL_ID = "inge_reminders";
    private static final int ALARM_REQUEST = 8301;
    private static final int OPEN_REQUEST = 8302;
    private static final int NOTIFICATION_ID = 8303;
    private static final int PERMISSION_REQUEST = 8304;
    private static final int QUIET_FROM_HOUR = 21;
    private static final int QUIET_UNTIL_HOUR = 8;
    private static final int DAILY_HOUR = 18;

    private InGeReminderScheduler() {}

    /** Llamado desde C++ (PermissionHelper::updateReminders). */
    public static void update(Context context, boolean enabled, int pendingCount) {
        if (context == null)
            return;
        final Context app = context.getApplicationContext();
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean(KEY_ENABLED, enabled)
                .putInt(KEY_PENDING, Math.max(0, pendingCount))
                .apply();
        final AlarmManager alarms = (AlarmManager) app.getSystemService(Context.ALARM_SERVICE);
        if (alarms == null)
            return;
        final PendingIntent trigger = PendingIntent.getBroadcast(app, ALARM_REQUEST,
                new Intent(app, Receiver.class),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        if (!enabled || pendingCount <= 0) {
            alarms.cancel(trigger);
            android.util.Log.i("InGeReminders", "INGE_REMINDER_CANCELLED");
            return;
        }
        requestPermissionIfNeeded(app);
        final Calendar next = Calendar.getInstance();
        next.set(Calendar.HOUR_OF_DAY, DAILY_HOUR);
        next.set(Calendar.MINUTE, 0);
        next.set(Calendar.SECOND, 0);
        if (next.getTimeInMillis() <= System.currentTimeMillis())
            next.add(Calendar.DAY_OF_YEAR, 1);
        alarms.setInexactRepeating(AlarmManager.RTC, next.getTimeInMillis(),
                AlarmManager.INTERVAL_DAY, trigger);
        android.util.Log.i("InGeReminders", "INGE_REMINDER_SCHEDULED pending=" + pendingCount);
    }

    private static void requestPermissionIfNeeded(Context app) {
        if (Build.VERSION.SDK_INT < 33
                || app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                        == PackageManager.PERMISSION_GRANTED)
            return;
        final Activity activity = InGeQtActivity.currentActivity();
        if (activity == null)
            return;
        activity.runOnUiThread(() -> activity.requestPermissions(
                new String[] { Manifest.permission.POST_NOTIFICATIONS }, PERMISSION_REQUEST));
    }

    /** Alarma diaria: publica el recordatorio si sigue habiendo algo pendiente. */
    public static final class Receiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            final Context app = context.getApplicationContext();
            final SharedPreferences prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
            final int pending = prefs.getInt(KEY_PENDING, 0);
            if (!prefs.getBoolean(KEY_ENABLED, true) || pending <= 0)
                return;
            final Calendar now = Calendar.getInstance();
            final int hour = now.get(Calendar.HOUR_OF_DAY);
            if (hour >= QUIET_FROM_HOUR || hour < QUIET_UNTIL_HOUR)
                return;
            final int today = now.get(Calendar.YEAR) * 1000 + now.get(Calendar.DAY_OF_YEAR);
            if (prefs.getInt(KEY_LAST_DAY, -1) == today)
                return;
            if (Build.VERSION.SDK_INT >= 33
                    && app.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                            != PackageManager.PERMISSION_GRANTED)
                return;
            final NotificationManager manager =
                    (NotificationManager) app.getSystemService(Context.NOTIFICATION_SERVICE);
            if (manager == null)
                return;
            manager.createNotificationChannel(new NotificationChannel(CHANNEL_ID,
                    "Recordatorios de InGe+", NotificationManager.IMPORTANCE_DEFAULT));
            final Intent open = new Intent(app, InGeQtActivity.class)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            final PendingIntent content = PendingIntent.getActivity(app, OPEN_REQUEST, open,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            final int icon = app.getApplicationInfo().icon;
            final Notification publicVersion = new Notification.Builder(app, CHANNEL_ID)
                    .setSmallIcon(icon)
                    .setContentTitle("InGe+")
                    .setContentText("Tienes una actividad pendiente.")
                    .build();
            final Notification notification = new Notification.Builder(app, CHANNEL_ID)
                    .setSmallIcon(icon)
                    .setContentTitle("InGe+")
                    .setContentText("Tus calicatas tienen cambios pendientes. ¿Continuamos?")
                    .setVisibility(Notification.VISIBILITY_PRIVATE)
                    .setPublicVersion(publicVersion)
                    .setContentIntent(content)
                    .setAutoCancel(true)
                    .build();
            manager.notify(NOTIFICATION_ID, notification);
            prefs.edit().putInt(KEY_LAST_DAY, today).apply();
            android.util.Log.i("InGeReminders", "INGE_REMINDER_SHOWN");
        }
    }
}
