package com.ingema.ingeplus.fusionbridge;

// Pure JVM test: no Android build, device, token or mocked capture.
public final class FramePolicyTest {
    private static int checks;
    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
    public static void main(String[] args) {
        EarthFramePolicy p = new EarthFramePolicy();
        check(!p.accept(1, 100, 7, true), "closed session must reject frames");
        p.begin(1);
        check(!p.accept(1, 100, 7, true), "visibility unknown must reject");
        p.setVisible(true);
        check(!p.accept(1, 100, 7, false), "black/secure content must reject");
        check(p.accept(1, 200, 7, true), "first real frame accepted");
        check(p.fresh(2699), "fresh until 2499 ms without change");
        check(!p.accept(1, 300, 7, true), "identical frame is not progress");
        check(!p.fresh(2700), "same pixels expire at 2500 ms");
        check(!p.accept(1, 400, 9, true), "expired transport timestamps rejected");
        check(p.accept(1, 2800, 9, true), "new changing frame restores freshness");
        check(!p.accept(1, 2799, 10, true), "out of order rejected");
        p.setVisible(false);
        check(!p.fresh(2801), "hidden source clears freshness immediately");
        check(!p.accept(1, 2900, 10, true), "hidden source rejected");
        p.setVisible(true);
        check(!p.fresh(2901), "visibility must not revive cached pixels");
        p.stop();
        check(!p.accept(1, 3000, 10, true), "revoked session rejected");
        p.begin(2);
        p.setVisible(true);
        check(!p.accept(1, 3100, 11, true), "late frame from old session rejected");
        check(p.accept(2, 3100, 11, true), "new session can receive frames");
        check(!p.fresh(3000), "clock before last frame rejected");
        check(!EarthInputController.rejectionFor("zoomIn").isEmpty(), "zoom cannot claim success");
        check(!EarthInputController.rejectionFor("panLeft").isEmpty(), "pan cannot claim success");
        check(EarthInputController.rejectionFor("flyTo").contains("UNSUPPORTED"), "old JS command rejected");
        check(EarthSessionPolicy.shouldRecover(0, true, true), "retained Qt recovers even if a late consent result changes diagnostic text");
        check(!EarthSessionPolicy.shouldRecover(0, false, true), "do not reopen before host resumes");
        check(!EarthSessionPolicy.shouldRecover(1, true, true), "do not replace a current native session");
        check(!EarthSessionPolicy.shouldRecover(0, true, false), "intentional closure must not reopen");
        check(!EarthSessionPolicy.shouldRecover(0, false, false), "initial JNI open queue must not repeatedly restart");
        System.out.println("FusionBridge policy: " + checks + " checks passed");
    }
}
