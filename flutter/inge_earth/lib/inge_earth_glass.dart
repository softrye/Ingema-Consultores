import 'package:flutter/material.dart';

import 'inge_earth_controller.dart';

enum InGeEarthGlassRole { clear, regular, emphasized }

/// Semantic visual system for the embedded Earth shell.
///
/// The rendering order mirrors the MIT liquid_glass_widgets standard path:
/// tightly clipped backdrop sampling, semantic tint, luminous/Fresnel-like
/// rim, directional specular light, and an explicit low-performance fallback.
class InGeEarthPalette {
  const InGeEarthPalette(this.tokens);

  final InGeEarthTokens tokens;

  bool get dark => tokens.isDark;
  bool get glass => tokens.isGlass;

  Color get canvas => dark ? const Color(0xff0e1318) : const Color(0xffedf2f4);
  Color get grouped => dark ? const Color(0xff0b1014) : const Color(0xffe7edef);
  Color get surface => dark ? const Color(0xff171e24) : const Color(0xfff7fafa);
  Color get surfaceElevated =>
      dark ? const Color(0xff252e36) : const Color(0xfffcfdfd);
  Color get field => dark ? const Color(0xff151c22) : const Color(0xfff2f6f7);
  Color get textPrimary =>
      dark ? const Color(0xfff1f4f5) : const Color(0xff17252d);
  Color get textSecondary =>
      dark ? const Color(0xffbac2c8) : const Color(0xff53646d);
  Color get textTertiary =>
      dark ? const Color(0xff89949d) : const Color(0xff74848c);
  Color get accent => dark ? const Color(0xff69b9f0) : const Color(0xff086ba8);
  Color get accentSoft =>
      dark ? const Color(0x3d63b8ee) : const Color(0x26086ba8);
  Color get success => dark ? const Color(0xff72d0a5) : const Color(0xff247a58);
  Color get warning => dark ? const Color(0xffefbf68) : const Color(0xff976200);
  Color get destructive =>
      dark ? const Color(0xffff9299) : const Color(0xffb83b45);
  Color get border => dark ? const Color(0x8a3d4a54) : const Color(0xb8c8d4d9);
  Color get glassBorder =>
      dark ? const Color(0x78dbeff7) : const Color(0xdbffffff);
  Color get glassHighlight =>
      dark ? const Color(0x8ae8faff) : const Color(0xf2ffffff);
  Color get glassShadow =>
      dark ? const Color(0x85000000) : const Color(0x42071a24);

  Color materialColor(InGeEarthGlassRole role) {
    if (!glass) {
      return role == InGeEarthGlassRole.emphasized ? surfaceElevated : surface;
    }
    final base = dark ? const Color(0xff1f282f) : const Color(0xfff0f8f9);
    final alpha = switch (role) {
      InGeEarthGlassRole.clear => 0.46,
      InGeEarthGlassRole.regular => 0.58,
      InGeEarthGlassRole.emphasized => 0.70,
    };
    return base.withValues(alpha: alpha);
  }
}

class InGeEarthGlassSurface extends StatelessWidget {
  const InGeEarthGlassSurface({
    super.key,
    required this.tokens,
    required this.child,
    this.role = InGeEarthGlassRole.regular,
    this.padding = EdgeInsets.zero,
    this.radius = 20,
    this.blurEnabled = true,
    this.highlightEnabled = true,
    this.elevation = 1,
    this.selected = false,
    this.pressed = false,
  });

  final InGeEarthTokens tokens;
  final Widget child;
  final InGeEarthGlassRole role;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blurEnabled;
  final bool highlightEnabled;
  final int elevation;
  final bool selected;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final palette = InGeEarthPalette(tokens);
    final premium = tokens.isGlass && !tokens.lowPerformance;
    final borderRadius = BorderRadius.circular(radius);
    final baseMaterial = palette.materialColor(role);
    final stateMaterial = pressed
        ? Color.lerp(baseMaterial, palette.textPrimary, 0.10)!
        : selected
        ? Color.lerp(baseMaterial, palette.accent, 0.20)!
        : baseMaterial;

    final material = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            stateMaterial,
            Color.lerp(
              stateMaterial,
              palette.dark ? const Color(0xff0e1318) : Colors.white,
              palette.glass ? (palette.dark ? 0.13 : 0.06) : 0.04,
            )!,
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (highlightEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _InGeGlassRimPainter(
                    radius: radius,
                    border: palette.glassBorder,
                    highlight: palette.glassHighlight,
                    accent: palette.accent,
                    dark: palette.dark,
                    dispersion: premium,
                    selected: selected,
                  ),
                ),
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    // Embedded Flutter surfaces can be composed below an inherited opacity
    // layer. Avoid a BackdropFilter there: Impeller cannot accept that opacity
    // for backdrop contents. The semantic glass material remains fully active.
    final filtered = material;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: elevation <= 0
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(
                    color: palette.glassShadow,
                    blurRadius: elevation >= 2 ? 26 : 18,
                    spreadRadius: -4,
                    offset: Offset(0, elevation >= 2 ? 10 : 6),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: filtered,
        ),
      ),
    );
  }
}

class _InGeGlassRimPainter extends CustomPainter {
  const _InGeGlassRimPainter({
    required this.radius,
    required this.border,
    required this.highlight,
    required this.accent,
    required this.dark,
    required this.dispersion,
    required this.selected,
  });

  final double radius;
  final Color border;
  final Color highlight;
  final Color accent;
  final bool dark;
  final bool dispersion;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(
      bounds.deflate(0.55),
      Radius.circular(radius),
    );
    final effectiveBorder = selected
        ? Color.lerp(border, accent, 0.48)!
        : border;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          highlight,
          effectiveBorder.withValues(alpha: effectiveBorder.a * 0.78),
          effectiveBorder.withValues(alpha: effectiveBorder.a * 0.34),
        ],
        stops: const <double>[0, 0.46, 1],
      ).createShader(bounds);
    canvas.drawRRect(outer, rim);

    final inner = RRect.fromRectAndRadius(
      bounds.deflate(1.75),
      Radius.circular((radius - 1.2).clamp(0, radius)),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = (dark ? Colors.white : accent).withValues(
          alpha: dark ? 0.075 : 0.045,
        ),
    );

    final specularPath = Path()
      ..moveTo(radius * 0.58, 1.4)
      ..cubicTo(
        size.width * 0.28,
        0.4,
        size.width * 0.58,
        0.8,
        size.width - radius * 0.62,
        2.0,
      );
    canvas.drawPath(
      specularPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          colors: <Color>[
            Colors.transparent,
            highlight.withValues(alpha: highlight.a * 0.82),
            Colors.transparent,
          ],
        ).createShader(bounds),
    );

    if (dispersion) {
      canvas.drawArc(
        bounds.deflate(2.1),
        -0.82,
        0.66,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = const Color(0x6658d8ff),
      );
      canvas.drawArc(
        bounds.deflate(2.5),
        2.34,
        0.58,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.65
          ..color = const Color(0x4dff6f91),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InGeGlassRimPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      border != oldDelegate.border ||
      highlight != oldDelegate.highlight ||
      accent != oldDelegate.accent ||
      dark != oldDelegate.dark ||
      dispersion != oldDelegate.dispersion ||
      selected != oldDelegate.selected;
}
