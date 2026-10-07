package com.ingema.ingeplus;

import android.content.Context;
import android.speech.tts.TextToSpeech;
import android.util.Log;

import java.util.Locale;

public final class InGeNarrator {
    private static final String TAG = "InGeNarrator";
    private static TextToSpeech tts;
    private static boolean ready = false;
    private static String pendingText = null;
    private static String pendingLocale = "es-PE";
    private static float pendingRate = 0.94f;
    private static float pendingPitch = 1.0f;

    private InGeNarrator() {}

    public static synchronized void initialize(Context context) {
        if (context == null || tts != null) return;
        Context appContext = context.getApplicationContext();
        tts = new TextToSpeech(appContext, status -> {
            ready = status == TextToSpeech.SUCCESS;
            if (!ready) {
                Log.w(TAG, "Motor TTS no disponible: " + status);
                return;
            }
            if (pendingText != null) {
                speakInternal(pendingText, pendingLocale, pendingRate, pendingPitch);
                pendingText = null;
            }
        });
    }

    public static synchronized void speak(Context context, String text, String localeTag, float rate, float pitch) {
        if (text == null || text.trim().isEmpty()) return;
        if (tts == null) initialize(context);
        if (!ready || tts == null) {
            pendingText = text;
            pendingLocale = localeTag == null ? "es-PE" : localeTag;
            pendingRate = rate;
            pendingPitch = pitch;
            return;
        }
        speakInternal(text, localeTag, rate, pitch);
    }

    private static void speakInternal(String text, String localeTag, float rate, float pitch) {
        if (tts == null) return;
        Locale locale = localeFromTag(localeTag);
        int languageResult = tts.setLanguage(locale);
        if (languageResult == TextToSpeech.LANG_MISSING_DATA ||
                languageResult == TextToSpeech.LANG_NOT_SUPPORTED) {
            tts.setLanguage(new Locale("es", "PE"));
        }
        tts.setSpeechRate(Math.max(0.70f, Math.min(1.15f, rate)));
        tts.setPitch(Math.max(0.80f, Math.min(1.20f, pitch)));
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ingeplus_first_experience");
    }

    private static Locale localeFromTag(String tag) {
        if (tag == null || tag.trim().isEmpty()) return new Locale("es", "PE");
        String normalized = tag.replace('_', '-');
        String[] parts = normalized.split("-");
        if (parts.length >= 2) return new Locale(parts[0], parts[1]);
        return new Locale(parts[0]);
    }

    public static void stop() {
        pendingText = null;
        if (tts != null) tts.stop();
    }
}
