import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'inge_liquid_glass.dart';
import 'ingema_brand.dart';

/// Fondo animado de Auth: video local en modo cover, sin audio, en bucle y sin
/// controles. El póster (primer fotograma del mismo video) se pinta al instante
/// para que nunca haya flash negro/blanco; el video aparece encima con un
/// fundido cuando entrega su primer fotograma. Si el video no inicia, Auth queda
/// sobre el póster y sigue siendo utilizable. Solo presentación: no toca Auth.
class AuthVideoBackground extends StatefulWidget {
  const AuthVideoBackground({required this.animate, super.key});

  /// false (movimiento reducido / perfil de ahorro): solo el póster estático.
  final bool animate;

  static const videoAsset = 'assets/auth/ingema_auth_video.mp4';
  static const posterAsset = 'assets/auth/ingema_auth_video_poster.jpg';

  @override
  State<AuthVideoBackground> createState() => _AuthVideoBackgroundState();
}

class _AuthVideoBackgroundState extends State<AuthVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _firstFrame = false;
  bool _appActive = true;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.animate) _start();
  }

  Future<void> _start() async {
    final controller = VideoPlayerController.asset(
      AuthVideoBackground.videoAsset,
      // Nunca toma el foco de audio del sistema (el video se reproduce mudo).
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      // Textura externa compuesta por Flutter (no platform view): el fondo y
      // cada vidrio dibujan la MISMA textura de este único decoder.
      viewType: VideoViewType.textureView,
    );
    _controller = controller;
    controller.addListener(_onVideoValue);
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      if (!mounted || _controller != controller) return;
      _syncPlayback();
    } catch (error) {
      debugPrint('AUTH_VIDEO_UNAVAILABLE $error');
      if (_controller == controller) _release();
    }
  }

  void _onVideoValue() {
    final value = _controller?.value;
    if (_firstFrame || value == null || !value.isInitialized) return;
    if (value.hasError) {
      debugPrint('AUTH_VIDEO_UNAVAILABLE ${value.errorDescription}');
      // Fuera de la notificación en curso del controlador.
      Future.microtask(_release);
      return;
    }
    if (value.position > Duration.zero) {
      setState(() => _firstFrame = true);
      // Liquid Glass vivo: los vidrios pasan del póster a la misma textura del
      // video (y el mismo tinte), alineada con el fondo. La captura estática
      // se renueva solo para el tono claro/oscuro del material.
      final controller = _controller!;
      InGeGlassBackdrop.setLiveLayer(
        context,
        (context) => Stack(
          fit: StackFit.expand,
          children: [
            AuthCoverVideo(controller: controller),
            const _AuthLegibilityTint(),
          ],
        ),
      );
      InGeGlassBackdrop.requestCapture(context);
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_appActive && _tickerEnabled) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _release({bool disposing = false}) {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onVideoValue);
    if (!disposing && mounted) {
      // Los vidrios vuelven al póster antes de liberar la textura.
      InGeGlassBackdrop.setLiveLayer(context, null);
      setState(() => _firstFrame = false);
    }
    controller?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPlayback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Superficie oculta por el host (TickerMode off): el video se pausa.
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant AuthVideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _start();
    } else {
      _release();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release(disposing: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fondo base INGEMA Deep: nunca hay flash blanco ni negro puro.
        const ColoredBox(color: IngemaBrand.deep),
        Image.asset(
          AuthVideoBackground.posterAsset,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Fondo animado InGe+',
          frameBuilder: (context, child, frame, synchronous) {
            if (frame != null) InGeGlassBackdrop.requestCapture(context);
            return child;
          },
        ),
        if (controller != null)
          AnimatedOpacity(
            opacity: _firstFrame ? 1 : 0,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            child: AuthCoverVideo(controller: controller),
          ),
        // Tinte de legibilidad compartido con el vidrio vivo.
        const _AuthLegibilityTint(),
      ],
    );
  }
}

/// Tinte de legibilidad: INGEMA Deep/Navy por alpha, más denso donde vive el
/// formulario (parte inferior). Lo usan el fondo y la capa viva del vidrio.
class _AuthLegibilityTint extends StatelessWidget {
  const _AuthLegibilityTint();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x47151a30), // Deep 28 %
          Color(0x381c2d50), // Navy 22 %
          Color(0x8c151a30), // Deep 55 %
          Color(0xd1151a30), // Deep 82 %
        ],
        stops: [0, .36, .66, 1],
      ),
    ),
  );
}

/// Geometría BoxFit.cover del video sobre un viewport (equivalente exacto a
/// FittedBox cover centrado). Única fuente de escala, recorte y offset para el
/// fondo y para el vidrio vivo.
@immutable
class AuthVideoGeometry {
  const AuthVideoGeometry._(this.coverScale, this.rect);

  factory AuthVideoGeometry.cover(Size video, Size viewport) {
    final scale = math.max(
      viewport.width / video.width,
      viewport.height / video.height,
    );
    final width = video.width * scale;
    final height = video.height * scale;
    return AuthVideoGeometry._(
      scale,
      Rect.fromLTWH(
        (viewport.width - width) / 2, // offsetX (recorte horizontal centrado)
        (viewport.height - height) / 2, // offsetY (recorte vertical centrado)
        width,
        height,
      ),
    );
  }

  final double coverScale;

  /// Rectángulo renderizado del video dentro del viewport (puede exceder sus
  /// bordes: esa parte es el recorte del cover).
  final Rect rect;
  double get renderedWidth => rect.width;
  double get renderedHeight => rect.height;
  double get offsetX => rect.left;
  double get offsetY => rect.top;
}

/// El video en modo cover con [AuthVideoGeometry]. El fondo y cada vidrio
/// instancian este mismo widget con el MISMO controlador: una sola textura y
/// un solo decoder, con geometría idéntica para el mismo viewport.
class AuthCoverVideo extends StatelessWidget {
  const AuthCoverVideo({required this.controller, super.key});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final video = controller.value.size;
      if (video.isEmpty || !constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
        return const SizedBox.expand();
      }
      final geometry = AuthVideoGeometry.cover(video, constraints.biggest);
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: geometry.rect,
              child: VideoPlayer(controller),
            ),
          ],
        ),
      );
    },
  );
}
