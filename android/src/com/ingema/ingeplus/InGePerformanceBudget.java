package com.ingema.ingeplus;

/** Immutable internal rendering/work budget. No user-visible quality tier exists. */
public final class InGePerformanceBudget {
    public final double targetFrameTimeMs;
    public final float sustainableRefreshHz;
    public final double renderScale;
    public final double animationBudget;
    public final double blurBudget;
    public final int backgroundWorkBudget;
    public final int cacheBudgetMb;
    public final int prefetchBudget;

    InGePerformanceBudget(double targetFrameTimeMs,
                          float sustainableRefreshHz,
                          double renderScale,
                          double animationBudget,
                          double blurBudget,
                          int backgroundWorkBudget,
                          int cacheBudgetMb,
                          int prefetchBudget) {
        this.targetFrameTimeMs = targetFrameTimeMs;
        this.sustainableRefreshHz = sustainableRefreshHz;
        this.renderScale = renderScale;
        this.animationBudget = animationBudget;
        this.blurBudget = blurBudget;
        this.backgroundWorkBudget = backgroundWorkBudget;
        this.cacheBudgetMb = cacheBudgetMb;
        this.prefetchBudget = prefetchBudget;
    }
}
