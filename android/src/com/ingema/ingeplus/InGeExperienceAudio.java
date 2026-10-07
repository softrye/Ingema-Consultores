package com.ingema.ingeplus;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.SoundPool;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Audio premium de la Primera Experiencia InGe+.
 * - Música ambiental con fundidos.
 * - Narraciones integradas ES/EN/QU.
 * - Sound design de baja latencia mediante SoundPool.
 * No requiere permisos ni conexión a internet.
 */
public final class InGeExperienceAudio {
    private static final String TAG = "InGeExperienceAudio";
    private static final Handler mainHandler = new Handler(Looper.getMainLooper());
    private static Context appContext;
    private static SoundPool soundPool;
    private static final Map<String, Integer> soundIds = new HashMap<>();
    private static MediaPlayer ambientPlayer;
    private static MediaPlayer narrationPlayer;
    private static float ambientVolume = 0.28f;
    private static float narrationVolume = 0.92f;
    private static float sfxVolume = 0.72f;
    private static boolean initialized = false;
    private static int fadeGeneration = 0;
    private static float currentAmbientVolume = 0f;

    private static final String[] SFX_NAMES = new String[] {
            "sfx_scene_forward", "sfx_scene_back", "sfx_tap", "sfx_select",
            "sfx_logo", "sfx_success", "sfx_map_ping", "sfx_sync",
            "sfx_privacy", "sfx_ready", "sfx_pulse", "sfx_offline", "sfx_online"
    };

    private InGeExperienceAudio() {}

    public static synchronized void initialize(Context context) {
        if (initialized || context == null) return;
        appContext = context.getApplicationContext();
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        soundPool = new SoundPool.Builder()
                .setMaxStreams(4)
                .setAudioAttributes(attrs)
                .build();
        for (String name : SFX_NAMES) {
            int id = rawId(name);
            if (id != 0) soundIds.put(name, soundPool.load(appContext, id, 1));
        }
        initialized = true;
        Log.i(TAG, "Audio premium inicializado. SFX=" + soundIds.size());
    }

    private static int rawId(String name) {
        if (appContext == null) return 0;
        return appContext.getResources().getIdentifier(name, "raw", appContext.getPackageName());
    }

    public static synchronized boolean hasBundledNarration(Context context, String languageCode) {
        initialize(context);
        String lang = normalizeLanguage(languageCode);
        return rawId("narr_" + lang + "_01") != 0;
    }

    public static synchronized void setVolumes(float ambient, float narration, float sfx) {
        ambientVolume = clamp(ambient, 0f, 1f);
        narrationVolume = clamp(narration, 0f, 1f);
        sfxVolume = clamp(sfx, 0f, 1f);
        if (ambientPlayer != null) ambientPlayer.setVolume(ambientVolume, ambientVolume);
        if (narrationPlayer != null) narrationPlayer.setVolume(narrationVolume, narrationVolume);
    }

    public static synchronized void playAmbient(Context context, float targetVolume) {
        initialize(context);
        ambientVolume = clamp(targetVolume, 0f, 1f);
        if (ambientPlayer == null) {
            int id = rawId("experience_ambient_loop");
            if (id == 0) return;
            ambientPlayer = MediaPlayer.create(appContext, id);
            if (ambientPlayer == null) return;
            ambientPlayer.setLooping(true);
            currentAmbientVolume = 0f;
            ambientPlayer.setVolume(0f, 0f);
        }
        if (!ambientPlayer.isPlaying()) ambientPlayer.start();
        fadeAmbientTo(ambientVolume, 650);
    }

    public static synchronized void stopAmbient(int fadeMs) {
        if (ambientPlayer == null) return;
        fadeAmbientTo(0f, Math.max(0, fadeMs));
        final MediaPlayer player = ambientPlayer;
        mainHandler.postDelayed(() -> {
            synchronized (InGeExperienceAudio.class) {
                if (player == ambientPlayer && player != null) {
                    try {
                        player.pause();
                        player.seekTo(0);
                        currentAmbientVolume = 0f;
                    } catch (Exception ignored) {}
                }
            }
        }, Math.max(0, fadeMs) + 40L);
    }

    private static void fadeAmbientTo(final float target, final int durationMs) {
        if (ambientPlayer == null) return;
        final int generation = ++fadeGeneration;
        final float start = currentAmbientVolume;
        final int steps = Math.max(1, durationMs / 30);
        for (int i = 0; i <= steps; i++) {
            final int step = i;
            mainHandler.postDelayed(() -> {
                synchronized (InGeExperienceAudio.class) {
                    if (generation != fadeGeneration || ambientPlayer == null) return;
                    float p = step / (float) steps;
                    float eased = p * p * (3f - 2f * p);
                    float volume = start + (target - start) * eased;
                    currentAmbientVolume = volume;
                    try { ambientPlayer.setVolume(volume, volume); } catch (Exception ignored) {}
                }
            }, (long) durationMs * i / steps);
        }
    }

    public static synchronized boolean playNarration(Context context, int sceneIndex,
                                                       String languageCode, float volume) {
        initialize(context);
        stopNarration();
        String lang = normalizeLanguage(languageCode);
        int safeScene = Math.max(0, Math.min(11, sceneIndex)) + 1;
        String name = String.format(Locale.US, "narr_%s_%02d", lang, safeScene);
        int id = rawId(name);
        if (id == 0 && !"es".equals(lang)) id = rawId(String.format(Locale.US, "narr_es_%02d", safeScene));
        if (id == 0) return false;
        narrationVolume = clamp(volume, 0f, 1f);
        narrationPlayer = MediaPlayer.create(appContext, id);
        if (narrationPlayer == null) return false;
        narrationPlayer.setVolume(narrationVolume, narrationVolume);
        narrationPlayer.setOnCompletionListener(mp -> {
            synchronized (InGeExperienceAudio.class) {
                if (mp == narrationPlayer) {
                    try { mp.release(); } catch (Exception ignored) {}
                    narrationPlayer = null;
                    if (ambientPlayer != null && ambientPlayer.isPlaying()) {
                        ambientPlayer.setVolume(ambientVolume, ambientVolume);
                    }
                }
            }
        });
        if (ambientPlayer != null && ambientPlayer.isPlaying()) {
            ambientPlayer.setVolume(ambientVolume * 0.38f, ambientVolume * 0.38f);
        }
        narrationPlayer.start();
        return true;
    }

    public static synchronized void stopNarration() {
        if (narrationPlayer != null) {
            final MediaPlayer player = narrationPlayer;
            narrationPlayer = null;

            try { player.setOnCompletionListener(null); } catch (Exception ignored) {}
            try { player.setOnErrorListener(null); } catch (Exception ignored) {}
            try {
                if (player.isPlaying())
                    player.pause();
            } catch (Exception ignored) {}
            try { player.reset(); } catch (Exception ignored) {}
            try { player.release(); } catch (Exception ignored) {}
        }

        if (ambientPlayer != null && ambientPlayer.isPlaying()) {
            currentAmbientVolume = ambientVolume;
            ambientPlayer.setVolume(ambientVolume, ambientVolume);
        }
    }

    public static synchronized void playSfx(Context context, String name, float volume) {
        initialize(context);
        if (soundPool == null || name == null) return;
        Integer id = soundIds.get(name);
        if (id == null) return;
        float v = clamp(volume, 0f, 1f) * sfxVolume;
        soundPool.play(id, v, v, 1, 0, 1f);
    }

    public static synchronized void stopAll() {
        stopNarration();
        stopAmbient(250);
    }

    public static synchronized void release() {
        fadeGeneration++;
        stopNarration();
        if (ambientPlayer != null) {
            try { ambientPlayer.release(); } catch (Exception ignored) {}
            ambientPlayer = null;
            currentAmbientVolume = 0f;
        }
        if (soundPool != null) {
            soundPool.release();
            soundPool = null;
        }
        soundIds.clear();
        initialized = false;
    }

    private static String normalizeLanguage(String code) {
        if (code == null) return "es";
        String value = code.trim().toLowerCase(Locale.US);
        if (value.startsWith("en")) return "en";
        if (value.startsWith("qu")) return "qu";
        return "es";
    }

    private static float clamp(float value, float min, float max) {
        return Math.max(min, Math.min(max, value));
    }
}
