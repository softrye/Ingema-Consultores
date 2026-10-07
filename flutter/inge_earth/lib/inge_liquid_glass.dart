import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Liquid Glass de InGe+ en superficies Flutter.
///
/// Es el mismo material del Dock (qml/Mobile/flowcore/GlobalContextDock.qml,
/// componente GlassSurface) llevado a la FlutterView:
///   backdrop capturado → luminancia → tono con histéresis → tokens →
///   shader `liquidglass.frag` (port 1:1 en shaders/liquidglass.frag).
/// Como el Dock, se hace UNA captura del fondo (no un BackdropFilter por
/// control) y cada superficie muestrea solo su rectángulo + margen.

/// Tokens del material: valores idénticos a GlobalContextDock.qml
/// (glassTint, fallbackGlass, rimLight, rimShade, rimSheen, edgeContrast,
/// glassSaturation, shadowColor) según `onDarkMaterial`.
@immutable
class InGeGlassTokens {
  const InGeGlassTokens(this.onDarkMaterial);

  final bool onDarkMaterial;

  Color get glassTint => onDarkMaterial
      ? Color.from(alpha: .10, red: .08, green: .10, blue: .13)
      : Color.from(alpha: .02, red: .95, green: .97, blue: 1.0);
  Color get fallbackGlass => onDarkMaterial
      ? Color.from(alpha: .18, red: .30, green: .33, blue: .38)
      : Color.from(alpha: .14, red: .97, green: .98, blue: 1.0);
  double get rimLight => onDarkMaterial ? .30 : .34;
  double get rimShade => onDarkMaterial ? .08 : .07;
  double get rimSheen => onDarkMaterial ? .06 : .03;
  double get edgeContrast => onDarkMaterial ? 0 : .05;
  double get glassSaturation => 1.22;
  Color get shadowColor => Color.from(
    alpha: onDarkMaterial ? .22 : .10,
    red: .03,
    green: .08,
    blue: .15,
  );

  /// Velo de legibilidad sobre el MISMO material (patrón del menú del Dock:
  /// "legibility veil over the same material, no second glass engine").
  /// Auth usa texto claro sobre fotografía, por eso el velo es oscuro y se
  /// refuerza cuando el fondo es claro.
  Color get textVeil => onDarkMaterial
      ? Color.from(alpha: .16, red: .07, green: .09, blue: .12)
      : Color.from(alpha: .34, red: .05, green: .07, blue: .09);

  /// Histéresis del Dock (updateMaterialTone): oscuro < 0.5, claro > 0.6.
  static bool resolveOnDark(double luma, bool? previous) {
    if (luma < 0) return previous ?? true;
    if (luma < .5) return true;
    if (luma > .6) return false;
    return previous ?? luma < .55;
  }
}

/// Captura compartida del fondo que está detrás del vidrio.
class InGeGlassFrame {
  InGeGlassFrame(this.image, this.bytes, this.logicalSize);

  final ui.Image image;
  final ByteData bytes;
  final Size logicalSize;
  final Map<String, double> _lumaCache = <String, double>{};

  /// Luminancia robusta (media recortada 10 %) del rectángulo lógico, mismo
  /// criterio que DockContextClient._captureBackdrop.
  double lumaOf(Rect logical) {
    final key =
        '${logical.left.round()},${logical.top.round()},'
        '${logical.width.round()},${logical.height.round()}';
    final cached = _lumaCache[key];
    if (cached != null) return cached;
    final sx = image.width / logicalSize.width;
    final sy = image.height / logicalSize.height;
    final left = (logical.left * sx).floor().clamp(0, image.width - 1);
    final right = (logical.right * sx).ceil().clamp(left + 1, image.width);
    final top = (logical.top * sy).floor().clamp(0, image.height - 1);
    final bottom = (logical.bottom * sy).ceil().clamp(top + 1, image.height);
    final data = bytes.buffer.asUint8List();
    final samples = <double>[];
    for (var y = top; y < bottom; y += 3) {
      for (var x = left; x < right; x += 3) {
        final i = (y * image.width + x) * 4;
        samples.add(
          (0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) /
              255,
        );
      }
    }
    var luma = -1.0;
    if (samples.isNotEmpty) {
      samples.sort();
      final trim = samples.length ~/ 10;
      final kept = samples.sublist(trim, samples.length - trim);
      if (kept.isNotEmpty) luma = kept.reduce((a, b) => a + b) / kept.length;
    }
    if (_lumaCache.length > 32) _lumaCache.clear();
    return _lumaCache[key] = luma;
  }

  void dispose() => image.dispose();
}

/// Carga única del shader del Dock. `null` → degradación "shader-fallback"
/// (igual que GlassSurface.shaderFailed en QML).
final Future<ui.FragmentProgram?> _liquidGlassProgram = () async {
  try {
    final program = await ui.FragmentProgram.fromAsset(
      'shaders/liquidglass.frag',
    );
    debugPrint('INGE_AUTH_GLASS_SHADER_STATUS status=compiled');
    return program;
  } catch (error) {
    debugPrint('INGE_AUTH_GLASS_SHADER_STATUS status=error log=$error');
    return null;
  }
}();

/// Fuente VIVA del fondo (p. ej. el video de Auth). Construye la misma
/// composición que el fondo; cada [InGeGlassSurface] la monta con el tamaño
/// exacto del backdrop, alineada al píxel y recortada a su forma. Así el
/// contenido del vidrio cambia con cada frame de la fuente sin capturas
/// (sin `toImage`, sin readback GPU→CPU): la GPU compone la misma textura.
typedef InGeGlassLiveLayer = WidgetBuilder;

/// Dueño del fondo capturado. `background` es lo que se ve detrás del vidrio;
/// `child` contiene las superficies [InGeGlassSurface].
class InGeGlassBackdrop extends StatefulWidget {
  const InGeGlassBackdrop({
    required this.background,
    required this.child,
    this.name = 'auth',
    this.enabled = true,
    super.key,
  });

  final Widget background;
  final Widget child;
  final String name;
  final bool enabled;

  static bool isEnabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InGeGlassScope>()?.enabled ?? false;

  /// Solicita una nueva captura (p.ej. cuando la imagen de fondo termina de
  /// decodificarse). Idempotente y con rebote: nunca captura por frame.
  static void requestCapture(BuildContext context) {
    context
        .getInheritedWidgetOfExactType<_InGeGlassScope>()
        ?.state
        ._scheduleCapture();
  }

  /// Publica (o retira con `null`) la fuente viva del fondo. Mientras exista,
  /// el vidrio muestra esa fuente en tiempo real; la captura estática queda
  /// solo para el tono (luminancia) y como respaldo.
  static void setLiveLayer(BuildContext context, InGeGlassLiveLayer? layer) {
    final state = context
        .getInheritedWidgetOfExactType<_InGeGlassScope>()
        ?.state;
    if (state == null || !state.mounted) return;
    state.liveLayer.value = layer;
  }

  @override
  State<InGeGlassBackdrop> createState() => _InGeGlassBackdropState();
}

class _InGeGlassBackdropState extends State<InGeGlassBackdrop> {
  final GlobalKey _boundaryKey = GlobalKey();
  final ValueNotifier<InGeGlassFrame?> frame = ValueNotifier<InGeGlassFrame?>(
    null,
  );
  final ValueNotifier<ui.FragmentProgram?> programNotifier =
      ValueNotifier<ui.FragmentProgram?>(null);
  final ValueNotifier<InGeGlassLiveLayer?> liveLayer =
      ValueNotifier<InGeGlassLiveLayer?>(null);
  ui.FragmentProgram? get program => programNotifier.value;
  bool programResolved = false;
  bool _programRequested = false;
  Timer? _debounce;
  bool _busy = false;
  bool _pending = false;
  Size? _lastSize;

  RenderBox? get boundaryBox {
    final object = _boundaryKey.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  @override
  void initState() {
    super.initState();
    _ensureProgram();
  }

  void _ensureProgram() {
    if (_programRequested || !widget.enabled) return;
    _programRequested = true;
    _liquidGlassProgram.then((value) {
      if (!mounted) return;
      programResolved = true;
      // Las superficies montadas crean su shader y repintan.
      programNotifier.value = value;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    frame.value?.dispose();
    frame.dispose();
    programNotifier.dispose();
    liveLayer.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant InGeGlassBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled == oldWidget.enabled) return;
    if (widget.enabled) {
      _ensureProgram();
      _scheduleCapture();
    } else {
      _debounce?.cancel();
      final previous = frame.value;
      frame.value = null;
      previous?.dispose();
    }
  }

  void _scheduleCapture() {
    if (!widget.enabled) return;
    _debounce?.cancel();
    // Como el Dock: se captura cuando el contenido se asienta, no mientras
    // cambia (teclado, rotación).
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  Future<void> _capture() async {
    if (!mounted || !widget.enabled) return;
    if (_busy) {
      _pending = true;
      return;
    }
    final object = _boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary ||
        !object.attached ||
        !object.hasSize) {
      return;
    }
    final size = object.size;
    if (size.width < 1 || size.height < 1) return;
    final dpr = View.of(context).devicePixelRatio;
    final ratio = math.min(dpr, 1.25);
    _busy = true;
    try {
      final image = await object.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted || !widget.enabled || bytes == null) {
        image.dispose();
        return;
      }
      final previous = frame.value;
      frame.value = InGeGlassFrame(image, bytes, size);
      previous?.dispose();
      debugPrint(
        'INGE_AUTH_GLASS_BACKDROP owner=${widget.name} '
        'imageSize=${image.width}x${image.height} ratio=${ratio.toStringAsFixed(2)}',
      );
    } catch (_) {
      // Mejor esfuerzo: las superficies conservan el último frame válido o
      // el material de fallback del Dock.
    } finally {
      _busy = false;
      if (_pending && mounted) {
        _pending = false;
        _scheduleCapture();
      }
    }
  }

  @override
  Widget build(BuildContext context) => _InGeGlassScope(
    state: this,
    enabled: widget.enabled,
    child: Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (_lastSize != size) {
              _lastSize = size;
              _scheduleCapture();
            }
            return RepaintBoundary(key: _boundaryKey, child: widget.background);
          },
        ),
        widget.child,
      ],
    ),
  );
}

class _InGeGlassScope extends InheritedWidget {
  const _InGeGlassScope({required this.state, required this.enabled, required super.child});

  final _InGeGlassBackdropState state;
  final bool enabled;

  @override
  bool updateShouldNotify(_InGeGlassScope oldWidget) =>
      oldWidget.state != state || oldWidget.enabled != enabled;
}

/// Superficie Liquid Glass reutilizable. Parámetros con el mismo nombre y
/// significado que GlassSurface del Dock (strength, lens, frost, magnify,
/// frostTaps, elevation, cornerRadius).
class InGeGlassSurface extends StatefulWidget {
  const InGeGlassSurface({
    required this.child,
    this.cornerRadius = 29,
    this.strength = 1,
    this.lens = 1,
    this.frost = 4.5,
    this.magnify = 0,
    this.frostTaps = 12,
    this.elevation = true,
    this.veil = true,
    this.surfaceName = '',
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final double cornerRadius;
  final double strength;
  final double lens;
  final double frost;
  final double magnify;
  final double frostTaps;
  final bool elevation;
  final bool veil;
  final String surfaceName;
  final bool enabled;

  @override
  State<InGeGlassSurface> createState() => _InGeGlassSurfaceState();
}

class _InGeGlassSurfaceState extends State<InGeGlassSurface>
    with SingleTickerProviderStateMixin {
  final GlobalKey _paintKey = GlobalKey();
  // Aparición del backdrop (Behavior on backdropMix, 140 ms en el Dock).
  late final AnimationController _mix = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
  );
  ui.FragmentShader? _shader;
  bool? _onDark;
  String _mode = '';
  _InGeGlassScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.getInheritedWidgetOfExactType<_InGeGlassScope>();
    if (!identical(scope?.state, _scope?.state)) {
      _scope?.state.frame.removeListener(_onFrame);
      _scope?.state.programNotifier.removeListener(_onFrame);
      _scope?.state.liveLayer.removeListener(_onLiveLayer);
      _scope = scope;
      _scope?.state.frame.addListener(_onFrame);
      _scope?.state.programNotifier.addListener(_onFrame);
      _scope?.state.liveLayer.addListener(_onLiveLayer);
      _onFrame();
    } else {
      _scope = scope;
    }
  }

  void _onFrame() {
    if (!widget.enabled) return;
    final state = _scope?.state;
    if (state?.program != null && _shader == null) {
      _shader = state!.program!.fragmentShader();
    }
    if (state?.frame.value != null) {
      _mix.forward();
    }
  }

  // Solo cambia al publicar/retirar la fuente viva (no por frame de video).
  void _onLiveLayer() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant InGeGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) _onFrame();
    if (!widget.enabled) _mix.stop();
  }

  @override
  void dispose() {
    _scope?.state.frame.removeListener(_onFrame);
    _scope?.state.programNotifier.removeListener(_onFrame);
    _scope?.state.liveLayer.removeListener(_onLiveLayer);
    _mix.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _reportMode(String mode, bool onDark) {
    final key = '$mode/$onDark';
    if (key == _mode) return;
    _mode = key;
    debugPrint(
      'INGE_AUTH_GLASS_MODE surface=${widget.surfaceName} mode=$mode '
      'backdropTone=${onDark ? 'dark' : 'light'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final scope = _scope?.state;
    final live = scope?.liveLayer.value;
    final material = CustomPaint(
      key: _paintKey,
      painter: _InGeGlassPainter(
        surface: this,
        live: live != null,
        repaint: Listenable.merge(<Listenable?>[
          scope?.frame,
          scope?.programNotifier,
          _mix,
        ]),
      ),
      child: widget.child,
    );
    if (live == null || scope == null) return material;
    // Vidrio sobre fuente viva: la MISMA composición del fondo (misma
    // textura/decoder), alineada al píxel con el fondo real, recortada a la
    // forma del vidrio y desenfocada en GPU. Encima, el material del shader
    // (tinte, borde, specular, bisel) y el contenido del control.
    final sigma = math.max(2.0, widget.frost * 1.3);
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.cornerRadius),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.compose(
                outer: _saturationFilter(InGeGlassTokens(true).glassSaturation),
                inner: ui.ImageFilter.blur(
                  sigmaX: sigma,
                  sigmaY: sigma,
                  tileMode: TileMode.clamp,
                ),
              ),
              child: _InGeLiveBackdrop(
                backdrop: scope,
                repaint: Scrollable.maybeOf(context)?.position,
                child: Builder(builder: live),
              ),
            ),
          ),
        ),
        material,
      ],
    );
  }
}

/// Matriz de saturación (misma `glassSaturation` que el shader del Dock).
ColorFilter _saturationFilter(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return ColorFilter.matrix(<double>[
    ir + s, ig, ib, 0, 0, //
    ir, ig + s, ib, 0, 0, //
    ir, ig, ib + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
}

/// Monta la fuente viva con el tamaño exacto del backdrop y la desplaza, en
/// el momento de pintar, a la posición real del backdrop respecto de esta
/// superficie: el fragmento visible es exactamente lo que está detrás.
class _InGeLiveBackdrop extends SingleChildRenderObjectWidget {
  const _InGeLiveBackdrop({
    required this.backdrop,
    required this.repaint,
    required super.child,
  });

  final _InGeGlassBackdropState backdrop;
  final Listenable? repaint;

  @override
  _RenderInGeLiveBackdrop createRenderObject(BuildContext context) =>
      _RenderInGeLiveBackdrop(backdrop, repaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderInGeLiveBackdrop renderObject,
  ) {
    renderObject
      ..backdrop = backdrop
      ..repaint = repaint
      ..markNeedsLayout();
  }
}

class _RenderInGeLiveBackdrop extends RenderProxyBox {
  _RenderInGeLiveBackdrop(this.backdrop, this._repaint);

  _InGeGlassBackdropState backdrop;
  Listenable? _repaint;

  set repaint(Listenable? value) {
    if (identical(value, _repaint)) return;
    if (attached) _repaint?.removeListener(markNeedsPaint);
    _repaint = value;
    if (attached) _repaint?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _repaint?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _repaint?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    // Mismo viewport que el fondo => misma geometría cover (escala, recorte).
    final backdropSize = backdrop.boundaryBox?.size ?? size;
    child?.layout(BoxConstraints.tight(backdropSize));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final backBox = backdrop.boundaryBox;
    if (child == null || backBox == null) return;
    // Origen del backdrop en coordenadas locales de esta superficie.
    final delta = globalToLocal(backBox.localToGlobal(Offset.zero));
    context.paintChild(child, offset + delta);
  }
}

class _InGeGlassPainter extends CustomPainter {
  _InGeGlassPainter({
    required this.surface,
    required Listenable repaint,
    this.live = false,
  }) : widgetConfig = surface.widget,
       super(repaint: repaint);

  final _InGeGlassSurfaceState surface;
  final InGeGlassSurface widgetConfig;

  /// true: el contenido del vidrio lo pinta la fuente viva por debajo; este
  /// painter solo aporta sombra exterior, tinte y el material del shader
  /// (borde, specular, bisel) sin muestrear la captura estática.
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final w = widgetConfig;
    final radius = math.min(
      w.cornerRadius,
      math.min(size.width, size.height) / 2,
    );
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final backdrop = surface._scope?.state;
    final frame = backdrop?.frame.value;
    const margin = 6.0; // captureMargin del Dock

    // Rectángulo del ítem (+ margen) en coordenadas del fondo capturado.
    Rect? sourceRect;
    Rect? logicalRect;
    final selfBox = surface._paintKey.currentContext?.findRenderObject();
    final backBox = backdrop?.boundaryBox;
    if (frame != null &&
        selfBox is RenderBox &&
        selfBox.attached &&
        backBox != null) {
      final origin = backBox.localToGlobal(Offset.zero);
      final tl = selfBox.localToGlobal(const Offset(-margin, -margin)) - origin;
      final br =
          selfBox.localToGlobal(
            Offset(size.width + margin, size.height + margin),
          ) -
          origin;
      logicalRect = Rect.fromPoints(tl, br);
      final fs = frame.logicalSize;
      sourceRect = Rect.fromLTRB(
        logicalRect.left / fs.width,
        logicalRect.top / fs.height,
        logicalRect.right / fs.width,
        logicalRect.bottom / fs.height,
      );
    }

    final luma = frame != null && logicalRect != null
        ? frame.lumaOf(logicalRect.deflate(margin))
        : -1.0;
    final onDark = InGeGlassTokens.resolveOnDark(luma, surface._onDark);
    surface._onDark = onDark;
    final tokens = InGeGlassTokens(onDark);
    final captureActive = sourceRect != null;
    final shader = surface._shader;

    // Sombra suave (RectangularShadow del Dock: offset 0,2 · blur 8 · spread -2).
    if (w.elevation && (captureActive || live)) {
      if (live) {
        // El centro del vidrio es translúcido sobre el video: solo sombra exterior.
        canvas.save();
        canvas.clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect((Offset.zero & size).inflate(12)),
            Path()..addRRect(rrect),
          ),
        );
      }
      canvas.drawRRect(
        rrect.shift(const Offset(0, 2)).deflate(2),
        Paint()
          ..color = tokens.shadowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      if (live) canvas.restore();
    }

    if (live) {
      surface._reportMode('flutter-live', onDark);
      final tint = tokens.glassTint;
      canvas.drawRRect(
        rrect,
        Paint()..color = tint.withValues(alpha: math.min(1.0, tint.a * w.strength)),
      );
      if (shader == null || frame == null) {
        // Sin shader o aún sin textura de muestra: borde plano, nunca opaco.
        canvas.drawRRect(
          rrect.deflate(.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: tokens.rimLight * .8),
        );
        return _drawVeil(canvas, rrect, tokens);
      }
      // Shader en modo superposición: backdropMix 0 y fallback transparente
      // => solo borde fresnel, specular y bisel (alfa ~0 en el centro).
      final thickness = math.max(4.0, math.min(size.width, size.height) * .19);
      var i = 0;
      void f(double value) => shader.setFloat(i++, value);
      f(size.width);
      f(size.height);
      f(margin);
      f(radius);
      f(thickness);
      f(.2 * w.lens);
      f(w.frost);
      f(tokens.rimLight * w.strength);
      f(tokens.rimShade * w.strength);
      f(tokens.rimSheen * w.strength);
      f(tokens.glassSaturation);
      f(0); // backdropMix: el fondo lo aporta la capa viva
      f(w.magnify);
      f(tokens.edgeContrast * w.strength);
      f(w.frostTaps);
      f(tint.r);
      f(tint.g);
      f(tint.b);
      f(0); // tinte ya aplicado arriba
      f(1); // fallback blanco con alfa 0: realce del borde claro
      f(1);
      f(1);
      f(0);
      f(0);
      f(0);
      f(1);
      f(1);
      f(1.0);
      shader.setImageSampler(0, frame.image); // requerido; no se muestrea
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return _drawVeil(canvas, rrect, tokens);
    }

    if (shader == null) {
      // shader-fallback / aún resolviendo: material plano del Dock.
      surface._reportMode(
        backdrop?.programResolved == true ? 'shader-fallback' : 'pending',
        onDark,
      );
      canvas.drawRRect(rrect, Paint()..color = tokens.fallbackGlass);
      canvas.drawRRect(
        rrect.deflate(.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: tokens.rimLight * .8),
      );
    } else {
      surface._reportMode(
        captureActive ? 'flutter-backdrop' : 'flutter-fallback',
        onDark,
      );
      final mix = captureActive ? surface._mix.value : 0.0;
      final thickness = math.max(4.0, math.min(size.width, size.height) * .19);
      final tint = tokens.glassTint;
      final fallback = tokens.fallbackGlass;
      final src = sourceRect ?? const Rect.fromLTWH(0, 0, 1, 1);
      var i = 0;
      void f(double value) => shader.setFloat(i++, value);
      f(size.width); // itemSize
      f(size.height);
      f(margin);
      f(radius);
      f(thickness);
      f(.2 * w.lens); // refraction
      f(w.frost);
      f(tokens.rimLight * w.strength);
      f(tokens.rimShade * w.strength);
      f(tokens.rimSheen * w.strength);
      f(tokens.glassSaturation);
      f(mix); // backdropMix
      f(w.magnify);
      f(tokens.edgeContrast * w.strength);
      f(w.frostTaps);
      f(tint.r); // tint (alfa × strength, como el Dock)
      f(tint.g);
      f(tint.b);
      f(math.min(1.0, tint.a * w.strength));
      f(fallback.r);
      f(fallback.g);
      f(fallback.b);
      f(fallback.a);
      f(src.left); // sourceRect (u, v, w, h)
      f(src.top);
      f(src.width);
      f(src.height);
      f(1.0); // opacity
      if (frame != null) {
        shader.setImageSampler(0, frame.image);
      } else {
        // Sin captura el shader usa fallbackColor (backdropMix = 0); aun así
        // requiere una textura válida: no se dibuja hasta tenerla.
        canvas.drawRRect(rrect, Paint()..color = tokens.fallbackGlass);
        return _drawVeil(canvas, rrect, tokens);
      }
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    }
    _drawVeil(canvas, rrect, tokens);
  }

  void _drawVeil(Canvas canvas, RRect rrect, InGeGlassTokens tokens) {
    if (!widgetConfig.veil) return;
    canvas.drawRRect(rrect, Paint()..color = tokens.textVeil);
  }

  @override
  bool shouldRepaint(covariant _InGeGlassPainter oldDelegate) =>
      oldDelegate.widgetConfig != widgetConfig || oldDelegate.live != live;
}
