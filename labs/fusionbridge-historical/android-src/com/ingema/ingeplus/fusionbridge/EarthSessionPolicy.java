package com.ingema.ingeplus.fusionbridge;

/** Recreate the native module after Activity loss, never revive a capture token. */
public final class EarthSessionPolicy {
    private EarthSessionPolicy() {}
    public static boolean shouldRecover(long nativeSession, boolean hostResumed, boolean hostSessionLost) {
        return nativeSession == 0 && hostResumed && hostSessionLost;
    }
}
