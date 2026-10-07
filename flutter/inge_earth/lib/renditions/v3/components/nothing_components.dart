import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/rendition_theme.dart';
import '../../../inge_liquid_glass.dart';

class NothingCard extends StatelessWidget {
  const NothingCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    super.key,
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: RenditionTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: RenditionTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class NothingStat extends StatelessWidget {
  const NothingStat(
    this.label,
    this.value, {
    this.financial = false,
    super.key,
  });
  final String label, value;
  final bool financial;
  @override
  Widget build(BuildContext context) => NothingCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: .7,
            color: RenditionTokens.secondary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            fontSize: financial ? 24 : 32,
            height: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class NothingMetrics extends StatelessWidget {
  const NothingMetrics({
    required this.values,
    this.financial = false,
    super.key,
  });
  final List<(String, String)> values;
  final bool financial;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 290 ? 1 : 2;
      return Wrap(
        spacing: 10,
        children: [
          for (final value in values)
            SizedBox(
              width: (constraints.maxWidth - (columns - 1) * 10) / columns,
              child: NothingStat(value.$1, value.$2, financial: financial),
            ),
        ],
      );
    },
  );
}

class NothingStatus extends StatelessWidget {
  const NothingStatus(this.text, {this.solid = false, super.key});
  final String text;
  final bool solid;
  static String label(String value) => const {
    'SYNCED': 'Sincronizado', 'SYNCING': 'Sincronizando…',
    'PENDING_CREATE': 'Pendiente de sincronizar', 'PENDING_UPDATE': 'Cambios pendientes',
    'LOCAL_ONLY': 'Guardado local', 'CONFLICT': 'Conflicto pendiente',
    'NEEDS_RECONCILIATION': 'Requiere sincronización', 'ERROR': 'Error de sincronización',
    'RESERVE': 'Pendiente de subida', 'UPLOAD': 'Subiendo',
    'FINALIZE': 'Procesando', 'READY': 'Listo',
    'BORRADOR': 'Borrador', 'PRESENTADA': 'Presentada',
  }[value] ?? value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: solid ? RenditionTokens.ink : RenditionTokens.secondarySurface,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      label(text),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: solid ? Colors.white : RenditionTokens.ink,
      ),
    ),
  );
}

class NothingSection extends StatelessWidget {
  const NothingSection(this.title, {this.action, super.key});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class NothingNotice extends StatelessWidget {
  const NothingNotice(this.text, {this.retry, super.key});
  final String text;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => NothingCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(LucideIcons.info, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (retry != null)
          IconButton(
            onPressed: retry,
            tooltip: 'Reintentar',
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
      ],
    ),
  );
}

class NothingHeading extends StatelessWidget {
  const NothingHeading(
    this.title,
    this.subtitle, {
    this.onBack,
    this.trailing,
    super.key,
  });
  final String title, subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: InGeGlassSurface(
      enabled: InGeGlassBackdrop.isEnabled(context),
      cornerRadius: 12,
      frostTaps: 4,
      lens: .25,
      elevation: false,
      veil: false,
      surfaceName: 'renditions-heading',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onBack != null)
                IconButton(
                  onPressed: onBack,
                  tooltip: 'Volver',
                  icon: const Icon(LucideIcons.arrowLeft),
                )
              else
                const Text(
                  'InGe+',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              const Spacer(),
              const NothingDots(),
              const SizedBox(width: 16),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: RenditionTokens.secondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

class NothingDots extends StatelessWidget {
  const NothingDots({super.key});
  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: CustomPaint(size: Size(42, 42), painter: _Dots()),
  );
}

// Adapted from local patterns_canvas Dots (MIT, Minas Giannekas, 2021).
// See docs/RENDITIONS_V3_DONORS.md for the retained license.
class _Dots extends CustomPainter {
  const _Dots();
  @override
  void paint(Canvas canvas, Size size) {
    final side = max(size.width, size.height) / 3;
    final path = Path();
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        path.addOval(
          Rect.fromCircle(
            center: Offset((x + .5) * side, (y + .5) * side),
            radius: .9,
          ),
        );
      }
    }
    canvas.drawPath(path, Paint()..color = RenditionTokens.ink);
  }

  @override
  bool shouldRepaint(covariant _Dots oldDelegate) => false;
}

/// Indicador propio de InGe+ (tres puntos en secuencia), idéntico al
/// FlowThreeBalls de QML: periodo 1050 ms (sube 300, baja 300, reposa 450),
/// desfase de 150 ms por punto. Implementación nativa independiente; un único
/// AnimationController. Inline, nunca overlay.
class NothingThreeBalls extends StatefulWidget {
  const NothingThreeBalls({
    this.color = RenditionTokens.ink,
    this.ballSize = 8,
    this.spacing = 6,
    this.travel = 4,
    super.key,
  });
  final Color color;
  final double ballSize;
  final double spacing;
  final double travel;

  @override
  State<NothingThreeBalls> createState() => _NothingThreeBallsState();
}

class _NothingThreeBallsState extends State<NothingThreeBalls>
    with SingleTickerProviderStateMixin {
  static const int _periodMs = 1050;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _periodMs),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 0 = reposo, 1 = arriba.
  double _lift(int i) {
    final t = (_controller.value * _periodMs - i * 150) % _periodMs;
    if (t < 300) return Curves.easeOutSine.transform(t / 300);
    if (t < 600) return 1 - Curves.easeInSine.transform((t - 300) / 300);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return ExcludeSemantics(
      child: SizedBox(
        width: w.ballSize * 3 + w.spacing * 2,
        height: w.ballSize + w.travel,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            children: [
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: i * (w.ballSize + w.spacing),
                  top: w.travel * (1 - _lift(i)),
                  child: Container(
                    width: w.ballSize,
                    height: w.ballSize,
                    decoration: BoxDecoration(
                      color: w.color.withValues(alpha: .9),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton estático de filas con un único pulso de opacidad (sin shimmer).
class NothingSkeletonRows extends StatefulWidget {
  const NothingSkeletonRows({this.count = 4, super.key});
  final int count;

  @override
  State<NothingSkeletonRows> createState() => _NothingSkeletonRowsState();
}

class _NothingSkeletonRowsState extends State<NothingSkeletonRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
    lowerBound: .55,
    upperBound: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(double widthFactor, double height) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: RenditionTokens.divider,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando',
    child: FadeTransition(
      opacity: _pulse,
      child: Column(
        children: [
          for (var i = 0; i < widget.count; i++)
            Container(
              height: 76,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RenditionTokens.surface,
                border: Border.all(color: RenditionTokens.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _bar(i.isEven ? .55 : .42, 12),
                  _bar(.3, 9),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
