class InGeEarthTokens {
  const InGeEarthTokens({
    this.themeMode = 'dark',
    this.motionScale = 1.0,
    this.glassIntensity = 0.72,
    this.performanceProfile = 'BALANCED',
  });

  final String themeMode;
  final double motionScale;
  final double glassIntensity;
  final String performanceProfile;

  String get normalizedThemeMode => themeMode.trim().toLowerCase();

  bool get isGlass =>
      normalizedThemeMode.startsWith('glass') || glassIntensity >= 0.9;

  bool get isDark =>
      normalizedThemeMode == 'dark' ||
      normalizedThemeMode == 'glass' ||
      normalizedThemeMode == 'glass-dark';

  bool get reducedMotion => motionScale <= 0.01;

  bool get lowPerformance {
    final profile = performanceProfile.trim().toUpperCase();
    return profile == 'PERFORMANCE' ||
        profile == 'SAFE' ||
        profile == 'REDUCED_MOTION';
  }
}
