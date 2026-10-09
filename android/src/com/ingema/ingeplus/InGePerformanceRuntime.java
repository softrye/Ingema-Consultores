package com.ingema.ingeplus;

import android.app.ActivityManager;
import android.app.Application;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.ConfigurationInfo;
import android.content.pm.PackageManager;
import android.graphics.Point;
import android.os.Build;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;
import android.view.Display;
import android.view.Window;
import android.view.WindowManager;

import androidx.core.performance.DefaultDevicePerformance;
import androidx.metrics.performance.FrameData;
import androidx.metrics.performance.JankStats;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Process-local adaptive runtime. Detection is cached, does no benchmark and never
 * emits per-frame logs or uploads telemetry.
 */
public final class InGePerformanceRuntime {
    public enum DeviceTier { ULTRA_LOW, LOW, MEDIUM, MEDIUM_HIGH, HIGH }

    public enum State {
        HOME, IDLE_GLASS, CALICATAS, RENDICIONES, DOCUMENTOS
    }

    private enum OverrideMode { AUTO, FORCE_CONSERVATIVE, FORCE_BALANCED, FORCE_MAX }

    public static final class Capabilities {
        public final int sdk;
        public final long totalMemoryBytes;
        public final int memoryClassMb;
        public final boolean lowRamDevice;
        public final int logicalCores;
        public final int widthPixels;
        public final int heightPixels;
        public final long pixelCount;
        public final float[] supportedRefreshRates;
        public final float currentRefreshHz;
        public final int mediaPerformanceClass;
        public final boolean powerSaveMode;
        public final int thermalStatus;
        public final int requiredOpenGlEsVersion;
        public final boolean vulkanSupported;
        public final String flutterRenderer;

        private Capabilities(int sdk, long totalMemoryBytes, int memoryClassMb,
                             boolean lowRamDevice, int logicalCores,
                             int widthPixels, int heightPixels,
                             float[] supportedRefreshRates, float currentRefreshHz,
                             int mediaPerformanceClass, boolean powerSaveMode,
                             int thermalStatus, int requiredOpenGlEsVersion,
                             boolean vulkanSupported, String flutterRenderer) {
            this.sdk = sdk;
            this.totalMemoryBytes = totalMemoryBytes;
            this.memoryClassMb = memoryClassMb;
            this.lowRamDevice = lowRamDevice;
            this.logicalCores = logicalCores;
            this.widthPixels = widthPixels;
            this.heightPixels = heightPixels;
            this.pixelCount = (long) widthPixels * (long) heightPixels;
            this.supportedRefreshRates = supportedRefreshRates.clone();
            this.currentRefreshHz = currentRefreshHz;
            this.mediaPerformanceClass = mediaPerformanceClass;
            this.powerSaveMode = powerSaveMode;
            this.thermalStatus = thermalStatus;
            this.requiredOpenGlEsVersion = requiredOpenGlEsVersion;
            this.vulkanSupported = vulkanSupported;
            this.flutterRenderer = flutterRenderer;
        }
    }

    public static final class FrameSnapshot {
        public final long frameCount;
        public final long jankCount;
        public final int recentFrameCount;
        public final int recentJankCount;
        public final double averageFrameTimeMs;
        public final double p95FrameTimeMs;
        public final State state;

        private FrameSnapshot(long frameCount, long jankCount, int recentFrameCount,
                              int recentJankCount, double averageFrameTimeMs,
                              double p95FrameTimeMs, State state) {
            this.frameCount = frameCount;
            this.jankCount = jankCount;
            this.recentFrameCount = recentFrameCount;
            this.recentJankCount = recentJankCount;
            this.averageFrameTimeMs = averageFrameTimeMs;
            this.p95FrameTimeMs = p95FrameTimeMs;
            this.state = state;
        }
    }

    private static final int FRAME_WINDOW = 120;
    private static volatile InGePerformanceRuntime instance;

    private final Capabilities capabilities;
    private final DeviceTier deviceTier;
    private final Context appContext;
    private final InGePerformanceBudget baseBudget;
    private volatile InGePerformanceBudget budget;
    private final double[] recentFrameMs = new double[FRAME_WINDOW];
    private final boolean[] recentJank = new boolean[FRAME_WINDOW];
    private int recentCursor;
    private int recentSize;
    private long frameCount;
    private long jankCount;
    private long budgetVersion = 1L;
    private volatile State state = State.HOME;
    private JankStats jankStats;

    private InGePerformanceRuntime(Window window, OverrideMode overrideMode) {
        appContext = window.getContext().getApplicationContext();
        capabilities = detect(window);
        deviceTier = classifyTier(capabilities, overrideMode);
        baseBudget = deriveBudget(capabilities, deviceTier);
        budget = baseBudget;
        Log.i("InGePerformance", "INGE_ADAPTIVE_RUNTIME sdk=" + capabilities.sdk
                + " ramMb=" + (capabilities.totalMemoryBytes / (1024L * 1024L))
                + " memoryClassMb=" + capabilities.memoryClassMb
                + " lowRam=" + capabilities.lowRamDevice
                + " cores=" + capabilities.logicalCores
                + " pixels=" + capabilities.pixelCount
                + " refresh=" + capabilities.currentRefreshHz
                + " supported=" + Arrays.toString(capabilities.supportedRefreshRates)
                + " performanceClass=" + capabilities.mediaPerformanceClass
                + " powerSave=" + capabilities.powerSaveMode
                + " thermal=" + capabilities.thermalStatus
                + " gles=0x" + Integer.toHexString(capabilities.requiredOpenGlEsVersion)
                + " hardwareVulkan=" + capabilities.vulkanSupported
                + " qtBackend=reported-by-GraphicsCore"
                + " flutter=" + capabilities.flutterRenderer
                + " override=" + overrideMode);
        Log.i("InGePerformance", "INGE_PERFORMANCE_BUDGET refreshHz="
                + budget.sustainableRefreshHz + " frameMs=" + budget.targetFrameTimeMs
                + " renderScale=" + budget.renderScale
                + " animation=" + budget.animationBudget
                + " blur=" + budget.blurBudget
                + " background=" + budget.backgroundWorkBudget
                + " cacheMb=" + budget.cacheBudgetMb
                + " prefetch=" + budget.prefetchBudget);
    }

    public static InGePerformanceRuntime initialize(Window window) {
        InGePerformanceRuntime value = instance;
        if (value == null) {
            synchronized (InGePerformanceRuntime.class) {
                value = instance;
                if (value == null) {
                    value = new InGePerformanceRuntime(window, readDebugOverride(window));
                    instance = value;
                }
            }
        }
        value.attachJankStats(window);
        return value;
    }

    public static InGePerformanceRuntime get() {
        return instance;
    }

    public Capabilities capabilities() { return capabilities; }
    public DeviceTier deviceTier() { return deviceTier; }
    public InGePerformanceBudget budget() { return budget; }
    public long budgetVersion() { return budgetVersion; }

    public void setState(State nextState) {
        if (nextState != null) state = nextState;
    }

    public void setTrackingEnabled(boolean enabled) {
        if (jankStats != null) jankStats.setTrackingEnabled(enabled);
    }

    public synchronized FrameSnapshot snapshot() {
        if (recentSize == 0) {
            return new FrameSnapshot(frameCount, jankCount, 0, 0, 0.0, 0.0, state);
        }
        double total = 0.0;
        int windowJank = 0;
        double[] sorted = new double[recentSize];
        for (int i = 0; i < recentSize; ++i) {
            sorted[i] = recentFrameMs[i];
            total += sorted[i];
            if (recentJank[i]) ++windowJank;
        }
        Arrays.sort(sorted);
        int p95Index = Math.min(sorted.length - 1,
                Math.max(0, (int) Math.ceil(sorted.length * 0.95) - 1));
        return new FrameSnapshot(frameCount, jankCount, recentSize, windowJank,
                total / recentSize, sorted[p95Index], state);
    }

    private synchronized void recordFrame(FrameData frameData) {
        final double durationMs = frameData.getFrameDurationUiNanos() / 1_000_000.0;
        final boolean jank = frameData.isJank();
        recentFrameMs[recentCursor] = durationMs;
        recentJank[recentCursor] = jank;
        recentCursor = (recentCursor + 1) % FRAME_WINDOW;
        if (recentSize < FRAME_WINDOW) ++recentSize;
        ++frameCount;
        if (jank) ++jankCount;
    }

    private void attachJankStats(Window window) {
        if (jankStats != null || window == null) return;
        try {
            jankStats = JankStats.createAndTrack(window, this::recordFrame);
        } catch (Throwable error) {
            Log.w("InGePerformance", "INGE_JANKSTATS_UNAVAILABLE", error);
        }
    }

    private static Capabilities detect(Window window) {
        final Context context = window.getContext().getApplicationContext();
        final ActivityManager activityManager =
                (ActivityManager) context.getSystemService(Context.ACTIVITY_SERVICE);
        final ActivityManager.MemoryInfo memory = new ActivityManager.MemoryInfo();
        activityManager.getMemoryInfo(memory);

        final Display display = window.getWindowManager().getDefaultDisplay();
        final Point size = new Point();
        display.getRealSize(size);
        final Set<Float> rates = new LinkedHashSet<>();
        for (Display.Mode mode : display.getSupportedModes()) rates.add(mode.getRefreshRate());
        final List<Float> sortedRates = new ArrayList<>(rates);
        sortedRates.sort(Float::compare);
        final float[] refreshRates = new float[sortedRates.size()];
        for (int index = 0; index < sortedRates.size(); ++index)
            refreshRates[index] = sortedRates.get(index);

        final PowerManager powerManager =
                (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        final int thermal = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                ? powerManager.getCurrentThermalStatus() : -1;

        final PackageManager packageManager = context.getPackageManager();
        final ConfigurationInfo configurationInfo =
                activityManager.getDeviceConfigurationInfo();
        final boolean vulkan = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                && (packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL)
                || packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION));

        return new Capabilities(Build.VERSION.SDK_INT, memory.totalMem,
                activityManager.getMemoryClass(), activityManager.isLowRamDevice(),
                Math.max(1, Runtime.getRuntime().availableProcessors()),
                size.x, size.y, refreshRates, display.getRefreshRate(),
                new DefaultDevicePerformance().getMediaPerformanceClass(),
                powerManager.isPowerSaveMode(), thermal,
                configurationInfo == null ? 0 : configurationInfo.reqGlEsVersion,
                vulkan, "hardware-engine-selected");
    }

    private static DeviceTier classifyTier(Capabilities c,
                                             OverrideMode overrideMode) {
        double score = 0.0;
        final long memoryGiB = c.totalMemoryBytes / (1024L * 1024L * 1024L);
        if (c.lowRamDevice) score -= 3.0;
        if (memoryGiB >= 6) score += 2.0;
        else if (memoryGiB >= 4) score += 1.0;
        else if (memoryGiB <= 3) score -= 1.0;
        if (c.memoryClassMb >= 384) score += 2.0;
        else if (c.memoryClassMb >= 256) score += 1.0;
        else if (c.memoryClassMb <= 128) score -= 2.0;
        if (c.logicalCores >= 8) score += 1.0;
        else if (c.logicalCores <= 4) score -= 1.0;
        if (c.pixelCount > 4_000_000L) score -= 1.0;
        else if (c.pixelCount > 2_500_000L) score -= 0.5;
        if (c.mediaPerformanceClass >= Build.VERSION_CODES.TIRAMISU) score += 2.0;
        else if (c.mediaPerformanceClass >= Build.VERSION_CODES.R) score += 1.0;
        if (c.powerSaveMode) score -= 2.0;
        if (c.thermalStatus >= PowerManager.THERMAL_STATUS_MODERATE) score -= 2.0;

        if (overrideMode == OverrideMode.FORCE_CONSERVATIVE) score = -4.0;
        else if (overrideMode == OverrideMode.FORCE_BALANCED) score = 0.5;
        else if (overrideMode == OverrideMode.FORCE_MAX) score = 5.0;

        if (score <= -3.0 || c.lowRamDevice) return DeviceTier.ULTRA_LOW;
        if (score < 1.5
                || c.totalMemoryBytes < 4L * 1024L * 1024L * 1024L)
            return DeviceTier.LOW;
        if (score < 2.5) return DeviceTier.MEDIUM;
        if (score < 4.0) return DeviceTier.MEDIUM_HIGH;
        return DeviceTier.HIGH;
    }

    private static InGePerformanceBudget deriveBudget(Capabilities c,
                                                       DeviceTier tier) {

        final float maxRefresh = c.supportedRefreshRates.length == 0
                ? Math.max(1.0f, c.currentRefreshHz)
                : c.supportedRefreshRates[c.supportedRefreshRates.length - 1];
        final float refreshCeiling = tier == DeviceTier.ULTRA_LOW
                || tier == DeviceTier.LOW ? 60.0f
                : (tier == DeviceTier.MEDIUM ? 90.0f : maxRefresh);
        float sustainable = chooseRefresh(c.supportedRefreshRates,
                Math.min(maxRefresh, refreshCeiling), c.currentRefreshHz);
        // MEDIUM targets up to 90 Hz. Common 60/120 Hz panels expose no mode in
        // between: do not drop a mid-range device to 60 Hz, let the system pick.
        if (tier == DeviceTier.MEDIUM && sustainable <= 60.5f
                && maxRefresh > 60.5f)
            sustainable = maxRefresh;
        // A 3.x GiB device may report eight cores and a 256 MB heap, but it
        // still cannot sustain two embedded renderers at full resolution.
        final int cacheMb = Math.max(24, Math.min(128, c.memoryClassMb / 3));
        final boolean ultraLow = tier == DeviceTier.ULTRA_LOW;
        final boolean low = tier == DeviceTier.LOW;
        final boolean medium = tier == DeviceTier.MEDIUM;
        final boolean mediumHigh = tier == DeviceTier.MEDIUM_HIGH;
        return new InGePerformanceBudget(1000.0 / sustainable, sustainable,
                1.0,
                ultraLow ? 0.78 : (low ? 0.86 : (mediumHigh ? 1.08 : 1.0)),
                ultraLow ? 0.72 : (low ? 0.82 : 1.0),
                ultraLow ? 1 : (low ? 1 : (mediumHigh ? 3 : 2)), cacheMb,
                ultraLow ? 0 : (low ? 0 : (medium ? 1 : (mediumHigh ? 2 : 3))));
    }

    private static float chooseRefresh(float[] supported, float ceiling, float fallback) {
        float chosen = 0.0f;
        for (float refresh : supported) {
            if (refresh <= ceiling + 0.5f && refresh > chosen) chosen = refresh;
        }
        if (chosen <= 0.0f && supported.length > 0) chosen = supported[0];
        return chosen > 0.0f ? chosen : Math.max(1.0f, fallback);
    }

    private static OverrideMode readDebugOverride(Window window) {
        final Context context = window.getContext();
        final boolean debuggable = (context.getApplicationInfo().flags
                & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
        if (!debuggable || !(context instanceof android.app.Activity))
            return OverrideMode.AUTO;
        final String value = ((android.app.Activity) context).getIntent()
                .getStringExtra("inge.performance.override");
        if (value == null) return OverrideMode.AUTO;
        try {
            return OverrideMode.valueOf(value.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException ignored) {
            return OverrideMode.AUTO;
        }
    }
}
