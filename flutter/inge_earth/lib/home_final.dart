import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'inge_liquid_glass.dart';
import 'ingema_brand.dart';

// Identidad INGEMA: texto en Deep, secundario derivado y accion en Blue.
const _ink = IngemaBrand.deep;
const _muted = IngemaBrand.inkTertiary;
const _olive = IngemaBrand.blue;
const _paper = Color(0xfffdfdfd);
const _background = Color(0xfffafafa);

/// Projects existing host data; navigation and account ownership stay in Qt.
class InGeFinalHome extends StatelessWidget {
  const InGeFinalHome({required this.state, required this.onAction, super.key});
  final Map<String, dynamic> state;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final projection = state['homeProjection'];
    final header = projection is Map && projection['header'] is Map
        ? projection['header'] as Map
        : const <String, dynamic>{};
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: _olive,
          onPrimary: Colors.white,
          secondary: _olive,
          surface: _paper,
          onSurface: _ink,
        ),
        scaffoldBackgroundColor: _background,
        splashFactory: NoSplash.splashFactory,
        highlightColor: const Color(0x0c0654a2),
      ),
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.min(constraints.maxWidth, 480.0);
              final margin = (width * .04).clamp(14.0, 18.0);
              // Phone controls never shrink with the viewport. Wider phones
              // gain modest spacing while text still follows accessibility.
              final scale = (math.min(width, 480) / 412).clamp(1.0, 1.08);
              final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
              final extraType = math.max(0.0, textScale - 1);
              return Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          key: const PageStorageKey('inge-final-home-scroll'),
                          padding: EdgeInsets.fromLTRB(
                            margin,
                            14 * scale,
                            margin,
                            12 * scale,
                          ),
                          children: [
                            _FinalHomeHeader(
                              header: header,
                              scale: scale,
                              onAction: onAction,
                            ),
                            SizedBox(height: 20 * scale),
                            _EditorialIntro(scale: scale),
                            SizedBox(height: 18 * scale),
                            _EditorialPortal(
                              kind: _PortalKind.calicatas,
                              scale: scale,
                              extraType: extraType,
                              onTap: () => onAction('calicatas'),
                            ),
                            SizedBox(height: 12 * scale),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _EditorialPortal(
                                    kind: _PortalKind.documents,
                                    scale: scale,
                                    extraType: extraType,
                                    onTap: () => onAction('documents'),
                                  ),
                                ),
                                SizedBox(width: 12 * scale),
                                Expanded(
                                  child: _EditorialPortal(
                                    kind: _PortalKind.earth,
                                    scale: scale,
                                    extraType: extraType,
                                    onTap: () => onAction('earth'),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12 * scale),
                            _EditorialPortal(
                              kind: _PortalKind.renditions,
                              scale: scale,
                              extraType: extraType,
                              onTap: () => onAction('renditions'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

TextStyle _type(double size, {bool bold = false, Color color = _ink}) =>
    TextStyle(
      fontSize: size,
      height: 1.23,
      fontWeight: bold ? IngemaBrand.semibold : IngemaBrand.regular,
      color: color,
      letterSpacing: bold ? -.45 : -.1,
    );

BoxDecoration _surface(double radius, {bool border = true}) => BoxDecoration(
  color: _paper,
  borderRadius: BorderRadius.circular(radius),
  border: border ? Border.all(color: const Color(0xffe8e8e8), width: .7) : null,
  boxShadow: const [
    BoxShadow(color: Color(0x09000000), blurRadius: 15, offset: Offset(0, 5)),
  ],
);

class _Microtext extends StatelessWidget {
  const _Microtext(this.text, this.scale);
  final String text;
  final double scale;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 7 * scale,
      height: 1.7,
      letterSpacing: 1.25 * scale,
      color: _muted,
    ),
  );
}

class _FinalHomeHeader extends StatelessWidget {
  const _FinalHomeHeader({
    required this.header,
    required this.scale,
    required this.onAction,
  });
  final Map header;
  final double scale;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) {
    final name = header['name']?.toString() ?? 'InGe+';
    final role = header['role']?.toString() ?? 'Usuario';
    return Row(
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: 280 * scale),
            decoration: _surface(40 * scale, border: false),
            child: InGeGlassSurface(
              enabled: InGeGlassBackdrop.isEnabled(context),
              cornerRadius: 40 * scale,
              frostTaps: 4,
              lens: .35,
              elevation: false,
              veil: false,
              surfaceName: 'home-profile',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(40 * scale),
                  onTap: () => onAction('profile'),
                  child: Padding(
                    padding: EdgeInsets.all(4 * scale),
                    child: Row(
                      children: [
                        _ProfileAvatar(
                          name: name,
                          source: header['avatar']?.toString() ?? '',
                          size: 42 * scale,
                        ),
                        SizedBox(width: 9 * scale),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _type(13 * scale, bold: true),
                              ),
                              SizedBox(height: 2 * scale),
                              Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _type(11 * scale, color: _muted),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 7 * scale),
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 14 * scale,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 16 * scale),
        _HeaderButton(
          LucideIcons.search,
          'Buscar',
          scale,
          () => onAction('search'),
        ),
        SizedBox(width: 7 * scale),
        _HeaderButton(
          LucideIcons.bell,
          'Notificaciones',
          scale,
          () => onAction('notifications'),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.name,
    required this.source,
    required this.size,
  });
  final String name;
  final String source;
  final double size;
  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final fallback = ColoredBox(
      color: const Color(0xffe5e7e3),
      child: Center(
        child: Text(initials, style: _type(size * .34, bold: true)),
      ),
    );
    final uri = Uri.tryParse(source);
    ImageProvider? provider;
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      provider = NetworkImage(source);
    } else if (uri != null && uri.scheme == 'file') {
      provider = FileImage(File.fromUri(uri));
    } else if (source.startsWith('/')) {
      provider = FileImage(File(source));
    }
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: provider == null
              ? fallback
              : Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => fallback,
                ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton(this.icon, this.label, this.scale, this.onTap);
  final IconData icon;
  final String label;
  final double scale;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 48 * scale,
    child: Center(
      child: Container(
        width: 48 * scale,
        height: 48 * scale,
        decoration: _surface(40 * scale, border: false),
        child: InGeGlassSurface(
          enabled: InGeGlassBackdrop.isEnabled(context),
          cornerRadius: 40 * scale,
          frostTaps: 4,
          lens: .35,
          elevation: false,
          veil: false,
          surfaceName: 'home-header-control',
          child: IconButton(
            tooltip: label,
            padding: EdgeInsets.zero,
            onPressed: onTap,
            icon: Icon(icon, size: 24 * scale, color: _ink),
          ),
        ),
      ),
    ),
  );
}

class _EditorialIntro extends StatelessWidget {
  const _EditorialIntro({required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned(
        right: 0,
        top: 0,
        width: 112 * scale,
        height: 84 * scale,
        child: const Opacity(
          opacity: .65,
          child: _ReferenceVisual(crop: Rect.fromLTWH(610, 239, 116, 161)),
        ),
      ),
      Positioned(
        right: 4 * scale,
        top: 5 * scale,
        child: _Microtext('TERRITORIO\nDATOS\nRESULTADOS', scale),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INGE+',
            style: TextStyle(
              fontSize: 10.5 * scale,
              letterSpacing: 3.5 * scale,
              color: _muted,
            ),
          ),
          SizedBox(height: 5 * scale),
          Text(
            'Herramientas\npara un mejor territorio',
            style: _type(25 * scale, bold: true).copyWith(height: 1.08),
          ),
          SizedBox(height: 5 * scale),
          Text(
            'Registra, organiza, analiza y rinde. Todo en terreno.',
            style: _type(13 * scale, color: _muted),
          ),
        ],
      ),
    ],
  );
}

enum _PortalKind {
  calicatas(
    'Calicatas',
    'Registra y gestiona calicatas\nen terreno de forma simple\ny precisa.',
    'SUELOS\nTERRITORIO\nEVIDENCIA',
  ),
  documents(
    'Documentos',
    'Organiza, consulta\ny comparte archivos\ndel proyecto.',
    'ORDEN\nTRAZABILIDAD\nACCESO',
  ),
  earth(
    'InGe Earth',
    'Visualiza información\nterritorial en mapas\ninteractivos.',
    'TERRITORIO\nANÁLISIS\nDECISIONES',
  ),
  renditions(
    'Rendición de cuentas',
    'Gestiona gastos, comprobantes\ny reportes de forma clara y ordenada.',
    'TRANSPARENCIA\nCONTROL\nRESULTADOS',
  );

  const _PortalKind(this.title, this.description, this.words);
  final String title;
  final String description;
  final String words;
  bool get primary => this == calicatas;
  bool get compact => this == documents || this == earth;
}

class _EditorialPortal extends StatelessWidget {
  const _EditorialPortal({
    required this.kind,
    required this.scale,
    required this.extraType,
    required this.onTap,
  });
  final _PortalKind kind;
  final double scale;
  final double extraType;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final primary = kind.primary;
    final compact = kind.compact;
    final height =
        (primary
            ? 168
            : compact
            ? 158
            : 116) *
        scale;
    final textGrowth = (compact ? 135 : 110) * extraType * scale;
    final padding =
        (primary
            ? 18
            : compact
            ? 15
            : 16) *
        scale;
    return Semantics(
      button: true,
      label: '${kind.title}. ${kind.description.replaceAll('\n', ' ')}',
      onTap: onTap,
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: height + textGrowth),
        decoration: _surface(13 * scale),
        child: IntrinsicHeight(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13 * scale),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _PortalArtwork(kind: kind, scale: scale),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: const [
                          _paper,
                          Color(0xf5fdfdfd),
                          Color(0x00fdfdfd),
                        ],
                        stops: [0, compact ? .58 : .50, compact ? .92 : .74],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    (primary
                            ? 16
                            : compact
                            ? 15
                            : 10) *
                        scale,
                    padding,
                    (primary
                            ? 10
                            : compact
                            ? 15
                            : 5) *
                        scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (primary) ...[
                        Text(
                          'SUBAPP PRINCIPAL',
                          style: TextStyle(
                            fontSize: 8 * scale,
                            letterSpacing: 1.8 * scale,
                            color: _muted,
                          ),
                        ),
                        SizedBox(height: 8 * scale),
                      ],
                      Text(
                        kind.title,
                        style: _type((primary ? 27 : 17) * scale, bold: true),
                      ),
                      SizedBox(height: (primary ? 3 : 6) * scale),
                      Text(
                        kind.description,
                        style: _type(
                          (primary ? 14 : 12) * scale,
                          color: _muted,
                        ),
                      ),
                      const Spacer(),
                      _ArrowAffordance(scale: scale),
                    ],
                  ),
                ),
                Positioned(
                  right: (compact ? 13 : 6) * scale,
                  top: primary ? 7 * scale : null,
                  bottom: primary ? null : 12 * scale,
                  child: Container(
                    width: primary ? 61 * scale : null,
                    height: primary ? 46 * scale : null,
                    padding: EdgeInsets.all(primary ? 7 * scale : 0),
                    decoration: primary
                        ? BoxDecoration(
                            color: const Color(0xffeef0f1),
                            borderRadius: BorderRadius.circular(10 * scale),
                          )
                        : null,
                    child: _Microtext(kind.words, scale),
                  ),
                ),
                // One hit surface covers the photograph, text and arrow alike.
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: onTap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalArtwork extends StatelessWidget {
  const _PortalArtwork({required this.kind, required this.scale});
  final _PortalKind kind;
  final double scale;
  @override
  Widget build(BuildContext context) {
    if (kind.primary) {
      return Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            width: 185 * scale,
            height: 150 * scale,
            child: const _ReferenceVisual(
              // One continuous photograph removes the old sky/soil seam.
              // The host label above fully covers the sampled reference badge.
              crop: Rect.fromLTWH(474, 433, 364, 295),
            ),
          ),
        ],
      );
    }
    final (crop, width, right, top) = switch (kind) {
      _PortalKind.documents => (
        const Rect.fromLTWH(326, 789, 126, 180),
        73.0,
        0.0,
        20.0,
      ),
      _PortalKind.earth => (
        const Rect.fromLTWH(708, 781, 126, 240),
        77.0,
        0.0,
        14.0,
      ),
      _PortalKind.renditions => (
        const Rect.fromLTWH(483, 1067, 207, 172),
        117.0,
        68.0,
        0.0,
      ),
      _PortalKind.calicatas => throw StateError(
        'Primary artwork handled above',
      ),
    };
    return Stack(
      children: [
        Positioned(
          right: right * scale,
          top: top * scale,
          width: width * scale,
          height: (kind.compact ? 112 : 90) * scale,
          child: _ReferenceVisual(crop: crop),
        ),
      ],
    );
  }
}

class _ArrowAffordance extends StatelessWidget {
  const _ArrowAffordance({required this.scale});
  final double scale;
  @override
  Widget build(BuildContext context) => Container(
    width: 25 * scale,
    height: 25 * scale,
    decoration: _surface(30 * scale),
    child: Icon(LucideIcons.arrowRight, size: 16 * scale, color: _ink),
  );
}

/// Reuses the integrated reference, sampling illustration regions only.
/// Labels, controls and profile data are live widgets. ImageCache shares decoding.
class _ReferenceVisual extends StatelessWidget {
  const _ReferenceVisual({required this.crop});
  final Rect crop;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRect(
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = math.max(
            box.maxWidth / crop.width,
            box.maxHeight / crop.height,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left:
                    -crop.left * scale +
                    (box.maxWidth - crop.width * scale) / 2,
                top:
                    -crop.top * scale +
                    (box.maxHeight - crop.height * scale) / 2,
                width: 941 * scale,
                height: 1672 * scale,
                child: Image.asset(
                  'assets/home_final/approved_reference.png',
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              // Static edge fades blend the local crop into the paper surface.
              // No image resampling, blur or continuously running effect.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        _paper,
                        Color(0x00fdfdfd),
                        Color(0x00fdfdfd),
                        _paper,
                      ],
                      stops: [0, .08, .90, 1],
                    ),
                  ),
                ),
              ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _paper,
                        Color(0x00fdfdfd),
                        Color(0x00fdfdfd),
                        _paper,
                      ],
                      stops: [0, .10, .96, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
