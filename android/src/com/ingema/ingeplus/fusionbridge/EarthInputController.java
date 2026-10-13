package com.ingema.ingeplus.fusionbridge;

/** A captured image has no target input channel. Never inject into InGe+'s window. */
public final class EarthInputController {
    private EarthInputController() {}
    public static String rejectionFor(String command) {
        if ("zoomIn".equals(command) || "zoomOut".equals(command)
                || "panLeft".equals(command) || "panRight".equals(command)
                || "panUp".equals(command) || "panDown".equals(command)
                || "rotateLeft".equals(command) || "rotateRight".equals(command)
                || "touch".equals(command))
            return "EARTH_INPUT_NO_COOPERATIVE_CHANNEL";
        return "EARTH_INPUT_UNSUPPORTED_COMMAND";
    }
}
