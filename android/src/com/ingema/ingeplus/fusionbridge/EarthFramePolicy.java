package com.ingema.ingeplus.fusionbridge;

/** Pure policy shared with JVM tests. No repeated pixels counted as progress. */
public final class EarthFramePolicy {
    public static final long STALE_MS = 2500;
    private long session;
    private long observed = -1;
    private long changed = -1;
    private long fingerprint;
    private boolean visible;

    public void begin(long generation) {
        stop();
        session = generation;
    }
    public void stop() {
        session = 0;
        visible = false;
        observed = changed = -1;
    }
    public void setVisible(boolean value) {
        visible = value;
        if (!value) changed = -1;
    }
    public boolean accept(long generation, long now, long hash, boolean nonBlack) {
        if (generation == 0 || generation != session || !visible || now < observed)
            return false;
        observed = now;
        if (!nonBlack) {
            changed = -1;
            return false;
        }
        if (changed >= 0 && hash == fingerprint) return false;
        fingerprint = hash;
        changed = now;
        return true;
    }
    public boolean fresh(long now) {
        if (now < observed) return false;
        observed = now;
        return session != 0 && visible && changed >= 0 && now - changed < STALE_MS;
    }
}
