import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'phosphor_icon.dart';
import 'home_final.dart';
import 'ingema_brand.dart';
import 'auth_video_background.dart';
import 'inge_liquid_glass.dart';
import 'dock_context_client.dart';
import 'renditions/v3/renditions_root.dart';

const _host = MethodChannel('inge.home/host');

void runInGeHome() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('AUTH_DART_ROOT_STARTED');
  runApp(const InGeHomeApp());
}

class HomeTokens {
  const HomeTokens({
    this.dark = false,
    this.motionScale = 1,
    this.glassIntensity = .72,
    this.idleGlass = false,
    this.performanceProfile = 'balanced',
  });

  final bool dark;
  final double motionScale;
  final double glassIntensity;
  final bool idleGlass;
  final String performanceProfile;

  bool get lowPerformance =>
      performanceProfile == 'safe' ||
      performanceProfile == 'low' ||
      (int.tryParse(performanceProfile) ?? 0) >= 3;

  factory HomeTokens.fromMap(Map<Object?, Object?>? data) {
    final mode = data?['themeMode']?.toString() ?? 'light';
    return HomeTokens(
      dark: mode == 'dark',
      motionScale: (data?['motionScale'] as num?)?.toDouble() ?? 1,
      glassIntensity: (data?['glassIntensity'] as num?)?.toDouble() ?? .72,
      idleGlass:
          data?['idleGlass'] == true ||
          ((data?['glassIntensity'] as num?)?.toDouble() ?? 0) > 0,
      performanceProfile: data?['performanceProfile']?.toString() ?? 'balanced',
    );
  }
}

// Mirror of the semantic QML palette (FlowTheme) for the embedded Flutter
// surfaces. Keeps Auth, Security and Home on one Light/Dark/Glass language
// built on the official INGEMA palette (IngemaBrand).
class InGePalette {
  const InGePalette(this.tokens);

  final HomeTokens tokens;

  bool get dark => tokens.dark;
  Color get backgroundPrimary =>
      dark ? IngemaBrand.deep : const Color(0xffeef2f4);
  Color get backgroundSecondary =>
      dark ? IngemaBrand.deepShade : const Color(0xffe8eef1);
  Color get surfacePrimary =>
      dark ? IngemaBrand.navy : const Color(0xfff8fafa);
  Color get surfaceElevated => tokens.idleGlass
      ? (dark ? const Color(0xd1334262) : const Color(0xe8fcfdfd))
      : (dark ? const Color(0xff334262) : const Color(0xfffcfdfd));
  Color get glassRegular => tokens.idleGlass
      ? (dark ? const Color(0xb31c2d50) : const Color(0xc7f7fbfb))
      : surfacePrimary;
  Color get textPrimary => dark ? IngemaBrand.paperPrimary : IngemaBrand.deep;
  Color get textSecondary =>
      dark ? IngemaBrand.paperSecondary : IngemaBrand.inkSecondary;
  Color get textTertiary =>
      dark ? IngemaBrand.paperTertiary : IngemaBrand.inkTertiary;
  Color get accent => dark ? IngemaBrand.blueTint : IngemaBrand.blue;
  Color get success => dark ? IngemaBrand.greenTint : IngemaBrand.green;
  Color get border => dark ? const Color(0x70404f6c) : const Color(0xffdfe2e6);
  Color get glassBorder =>
      dark ? const Color(0x70d1edf7) : const Color(0xc7ffffff);
  Color get error => dark ? const Color(0xffff8a91) : const Color(0xffb83b45);
}

// Home owns the shell palette (same INGEMA tokens as InGePalette, with the
// Home glass alphas). Auth and Security use InGePalette.
class InGeHomePalette {
  const InGeHomePalette(this.tokens);

  final HomeTokens tokens;

  bool get dark => tokens.dark;
  Color get backgroundPrimary =>
      dark ? IngemaBrand.deep : const Color(0xffeef2f4);
  Color get backgroundSecondary =>
      dark ? const Color(0xff182440) : const Color(0xffe8eef1);
  Color get surfacePrimary =>
      dark ? IngemaBrand.navy : const Color(0xfff8fafa);
  Color get surfaceElevated => tokens.idleGlass
      ? (dark ? const Color(0xb3334262) : const Color(0xbdfcfdfd))
      : (dark ? const Color(0xff334262) : const Color(0xfffcfdfd));
  Color get glassRegular => tokens.idleGlass
      ? (dark ? const Color(0x942a3a5a) : const Color(0x9ef0f8f9))
      : surfacePrimary;
  Color get textPrimary => dark ? IngemaBrand.paperPrimary : IngemaBrand.deep;
  Color get textSecondary =>
      dark ? IngemaBrand.paperSecondary : IngemaBrand.inkSecondary;
  Color get textTertiary =>
      dark ? IngemaBrand.paperTertiary : IngemaBrand.inkTertiary;
  Color get accent => dark ? IngemaBrand.blueTint : IngemaBrand.blue;
  Color get success => dark ? IngemaBrand.greenTint : IngemaBrand.green;
  Color get border => dark ? const Color(0x8a404f6c) : const Color(0xffdfe2e6);
  Color get glassBorder =>
      dark ? const Color(0x78dbeff7) : const Color(0xdbffffff);
  Color get error => dark ? const Color(0xffff8a91) : const Color(0xffb83b45);
}

class InGeHomeMotion {
  const InGeHomeMotion(this.tokens);

  final HomeTokens tokens;
  static const profile = 'FLUID_NATIVE_60HZ';
  static const curve = Cubic(.05, .72, .20, 1);

  Duration duration(int milliseconds) => tokens.motionScale <= 0
      ? Duration.zero
      : Duration(milliseconds: (milliseconds * tokens.motionScale).round());
}

class InGeHomeApp extends StatefulWidget {
  const InGeHomeApp({super.key});

  @override
  State<InGeHomeApp> createState() => _InGeHomeAppState();
}

class _InGeHomeAppState extends State<InGeHomeApp> {
  HomeTokens _tokens = const HomeTokens();
  bool _hostVisible = true;
  // El primer uso de este engine en un arranque sin sesión es Auth. Este
  // estado visual seguro evita una superficie vacía si el host tarda en
  // entregar su estado inicial.
  String _surfaceMode = 'auth';
  // Hasta recibir el estado del host se pinta la bienvenida (idéntica al
  // splash QML de arranque), nunca el formulario: sin destello de login
  // durante la restauración de sesión.
  Map<String, dynamic> _authState = const <String, dynamic>{
    'accounts': <Object>[],
    'logged': false,
    'busy': false,
    'error': '',
    'phase': 'welcome',
  };
  bool _biometricAvailable = false;
  String? _vaultAccountId;
  bool _vaultReady = false;
  String? _lastHostStateSignature;

  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'inge_biometric_vault',
      preferencesKeyPrefix: 'inge_auth',
    ),
  );
  static const _vaultAccountKey = 'account_id';
  static const _vaultBindingKey = 'session_binding';

  @override
  void initState() {
    super.initState();
    _host.setMethodCallHandler((call) async {
      if (call.method == 'hostVisibility' && mounted) {
        final visible = call.arguments != false;
        if (visible == _hostVisible) return;
        if (!mounted) return;
        // Una superficie oculta no conserva un campo enfocado: al volver a
        // mostrarse no reabre el teclado por su cuenta.
        if (!visible) FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _hostVisible = visible);
        if (visible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {});
        }
      } else if (call.method == 'hostState' && mounted) {
        _applyHostState(Map<Object?, Object?>.from(call.arguments as Map));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_announceReady());
    });
    unawaited(_initialize());
    unawaited(_loadVault());
  }

  @override
  void dispose() {
    _host.setMethodCallHandler(null);
    DockContextClient.instance.clear('home');
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final values = await _host.invokeMapMethod<Object?, Object?>(
        'getHostState',
      );
      if (mounted && values != null) _applyHostState(values);
    } on PlatformException {
      // The native host keeps the QML Home visible when this entrypoint fails.
    }
  }

  Future<void> _announceReady() async {
    try {
      await _host.invokeMethod<void>('ready');
    } on PlatformException {
      // El estado por defecto mantiene Auth visible; una actualización del
      // host posterior sigue siendo aceptada por el handler instalado arriba.
    }
  }

  void _applyHostState(Map<Object?, Object?> values) {
    final nextTokens = HomeTokens.fromMap(values);
    final nextSurfaceMode = values['surfaceMode']?.toString() ?? _surfaceMode;
    final nextBiometricAvailable = values['biometricAvailable'] == true;
    Map<String, dynamic> authState = const <String, dynamic>{};
    final rawAuth = values['authState']?.toString() ?? '{}';
    final signature = jsonEncode(<Object?>[
      nextTokens.dark,
      nextTokens.motionScale,
      nextTokens.glassIntensity,
      nextTokens.idleGlass,
      nextTokens.performanceProfile,
      nextSurfaceMode,
      nextBiometricAvailable,
      rawAuth,
    ]);
    if (signature == _lastHostStateSignature) return;
    try {
      final decoded = jsonDecode(rawAuth);
      if (decoded is Map) authState = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    _lastHostStateSignature = signature;
    // Cambio de superficie (auth -> home, home <-> rendiciones): sin foco
    // heredado ni teclado reabierto durante la transición.
    if (nextSurfaceMode != _surfaceMode) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    setState(() {
      _tokens = nextTokens;
      _surfaceMode = nextSurfaceMode;
      _biometricAvailable = nextBiometricAvailable;
      _authState = authState;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          _host.invokeMethod<void>('firstMeaningfulFrame', nextSurfaceMode),
        );
      }
    });
    if (nextSurfaceMode == 'auth') debugPrint('AUTH_DART_STATE_RECEIVED');
    if (_vaultReady) unawaited(_notifyBiometricStatus());
  }

  Future<void> _notifyBiometricStatus() async {
    final status = _vaultAccountId != null
        ? (_biometricAvailable ? 'enabled' : 'enabled-unavailable')
        : (_biometricAvailable ? 'available' : 'unavailable');
    try {
      await _host.invokeMethod<void>('authRequest', <String, Object>{
        'type': 'biometricStatus',
        'status': status,
      });
    } on PlatformException {
      // El host QML conserva su estado previo si el canal se está cerrando.
    }
  }

  Future<void> _loadVault() async {
    try {
      final account = await _vault.read(key: _vaultAccountKey);
      final binding = await _vault.read(key: _vaultBindingKey);
      if (!mounted) return;
      setState(() {
        _vaultAccountId = binding == null || binding.isEmpty ? null : account;
        _vaultReady = true;
      });
      unawaited(_notifyBiometricStatus());
    } on PlatformException {
      if (mounted) {
        setState(() => _vaultReady = true);
        unawaited(_notifyBiometricStatus());
      }
    }
  }

  Future<bool> _authenticateBiometric() async {
    if (!_biometricAvailable) return false;
    try {
      return await _host.invokeMethod<bool>('authenticateBiometric') == true;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> _enableVault(String accountId) async {
    if (accountId.isEmpty || !await _authenticateBiometric()) return false;
    final random = Random.secure();
    final binding = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    try {
      await _vault.write(key: _vaultAccountKey, value: accountId);
      await _vault.write(key: _vaultBindingKey, value: binding);
      if (mounted) setState(() => _vaultAccountId = accountId);
      unawaited(_notifyBiometricStatus());
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _disableVault() async {
    try {
      await _vault.delete(key: _vaultAccountKey);
      await _vault.delete(key: _vaultBindingKey);
    } finally {
      if (mounted) setState(() => _vaultAccountId = null);
      unawaited(_notifyBiometricStatus());
    }
  }

  Future<void> _dispatchGlobalAction(String action) =>
      _host.invokeMethod<void>('navigate', <String, Object>{'action': action});

  static const List<DockAction> _homeDockActions = <DockAction>[
    DockAction('home', 'Inicio', 'nav.home', 'home.open', selected: true, priority: 10),
    DockAction('profile', 'Perfil', 'profile.user', 'home.profile', priority: 20),
    DockAction('settings', 'Ajustes', 'nav.settings', 'home.settings', priority: 30),
  ];

  /// Home states its semantic actions; the host dock renders them.
  void _syncHomeDockContext() {
    final homeVisible = _hostVisible &&
        _surfaceMode != 'auth' &&
        _surfaceMode != 'security' &&
        _surfaceMode != 'renditions';
    if (!homeVisible) {
      DockContextClient.instance.clear('home');
      return;
    }
    DockContextClient.instance.publish('home', 'home/main', _homeDockActions, (command) {
      final action = switch (command) {
        'home.profile' => 'profile',
        'home.settings' => 'settings',
        _ => 'home',
      };
      return _dispatchGlobalAction(action);
    });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHomeDockContext();
    });
    final dark = _tokens.dark;
    final palette = InGePalette(_tokens);
    final authWelcome =
        _surfaceMode == 'auth' &&
        (_authState['phase']?.toString() ?? 'login') == 'welcome';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Home',
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: palette.backgroundPrimary,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: IngemaBrand.blue,
              brightness: dark ? Brightness.dark : Brightness.light,
            ).copyWith(
              primary: palette.accent,
              onPrimary: dark ? IngemaBrand.deep : Colors.white,
              secondary: dark ? IngemaBrand.greenTint : IngemaBrand.green,
              onSecondary: dark ? IngemaBrand.deep : Colors.white,
              surface: palette.surfacePrimary,
              onSurface: palette.textPrimary,
              error: palette.error,
            ),
        // Tipografia corporativa INGEMA (Rubik), declarada en pubspec.yaml.
        fontFamily: IngemaBrand.fontFamily,
        useMaterial3: true,
      ),
      // The dock backdrop must see every route and overlay, so the boundary
      // wraps the Navigator rather than the first route only.
      builder: (context, child) => Actions(
        // Contrato global de foco (mismo que QML): en Android, Flutter no
        // suelta el foco al tocar fuera de un campo, así que el nodo seguía
        // activo y su conexión IME volvía a mostrar el teclado. Tocar un
        // botón, opción o superficie suelta el foco (unfocus de ámbito: sin
        // historial que restaurar). Tocar otro campo sigue dentro de su
        // TextFieldTapRegion y no dispara esta acción.
        actions: <Type, Action<Intent>>{
          EditableTextTapOutsideIntent:
              CallbackAction<EditableTextTapOutsideIntent>(
                onInvoke: (intent) {
                  intent.focusNode.unfocus();
                  return null;
                },
              ),
        },
        child: DockBackdropBoundary(child: child ?? const SizedBox.shrink()),
      ),
      home: TickerMode(
        enabled: _hostVisible,
        child: IgnorePointer(
          ignoring: !_hostVisible,
          // Cambio de superficie dentro de la FlutterView compartida
          // (auth → home, home ↔ rendiciones): fade + 8 px, 200 ms. Solo se
          // monta la superficie actual (sin estados duplicados).
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            layoutBuilder: (current, previous) =>
                current ?? const SizedBox.shrink(),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: AnimatedBuilder(
                animation: animation,
                child: child,
                builder: (context, inner) => Transform.translate(
                  offset: Offset(0, 8 * (1 - animation.value)),
                  child: inner,
                ),
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey<String>(
                authWelcome ? 'surface:auth-welcome' : 'surface:$_surfaceMode',
              ),
              child: authWelcome
              ? InGeAuthWelcome(tokens: _tokens, state: _authState)
              : _surfaceMode == 'auth'
              ? InGeAuthScreen(
                  tokens: _tokens,
                  state: _authState,
                  biometricAvailable: _biometricAvailable,
                  vaultReady: _vaultReady,
                  vaultAccountId: _vaultAccountId,
                  authenticateBiometric: _authenticateBiometric,
                )
              : _surfaceMode == 'security'
              ? InGeSecurityScreen(
                  tokens: _tokens,
                  state: _authState,
                  biometricAvailable: _biometricAvailable,
                  vaultReady: _vaultReady,
                  vaultAccountId: _vaultAccountId,
                  enableVault: _enableVault,
                  disableVault: _disableVault,
                )
              : _surfaceMode == 'renditions'
              ? InGeGlassBackdrop(
                  name: 'renditions',
                  enabled: _tokens.idleGlass &&
                      !_tokens.lowPerformance && _tokens.motionScale > 0,
                  background: const ColoredBox(color: Color(0xfff7f7f5)),
                  child: RenditionsRootV3(
                    dark: _tokens.dark,
                    onGlobalAction: _dispatchGlobalAction,
                  ),
                )
              : InGeGlassBackdrop(
                  name: 'home',
                  enabled: _tokens.idleGlass &&
                      !_tokens.lowPerformance && _tokens.motionScale > 0,
                  background: const ColoredBox(color: Color(0xfffafafa)),
                  child: InGeFinalHome(state: _authState, onAction: (action) {
                    unawaited(_host.invokeMethod<void>('navigate', {'action': action}));
                  }),
                ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bienvenida de auto-inicio. Vive en la superficie Auth (la FlutterView que
/// realmente está encima de QML) y es espejo exacto de WelcomeSplashV600, de
/// modo que splash QML → Auth(bienvenida) → Home no muestra saltos.
class InGeAuthWelcome extends StatefulWidget {
  const InGeAuthWelcome({required this.tokens, required this.state, super.key});

  final HomeTokens tokens;
  final Map<String, dynamic> state;

  @override
  State<InGeAuthWelcome> createState() => _InGeAuthWelcomeState();
}

class _InGeAuthWelcomeState extends State<InGeAuthWelcome> {
  Timer? _activityDelay;
  bool _showActivity = false;

  @override
  void initState() {
    super.initState();
    debugPrint('AUTOLOGIN_WELCOME_MOUNTED');
    // Sin retraso artificial: la actividad solo aparece si la espera real
    // supera ~700 ms (misma regla que el splash QML).
    _activityDelay = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showActivity = true);
    });
  }

  @override
  void dispose() {
    _activityDelay?.cancel();
    super.dispose();
  }

  static Color _hostColor(Object? raw, Color fallback) {
    final text = raw?.toString().trim() ?? '';
    if (!text.startsWith('#')) return fallback;
    final hex = text.substring(1);
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return fallback;
    if (hex.length == 6) return Color(0xff000000 | value);
    if (hex.length == 8) return Color(value);
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.state['welcome'];
    final welcome = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final dark = welcome['dark'] is bool
        ? welcome['dark'] == true
        : widget.tokens.dark;
    final background = _hostColor(
      welcome['background'],
      dark ? IngemaBrand.deep : const Color(0xfff6f8fb),
    );
    final title = _hostColor(
      welcome['title'],
      dark ? IngemaBrand.paperPrimary : IngemaBrand.deep,
    );
    final accent = _hostColor(welcome['accent'], IngemaBrand.blue);
    final titleSize = (welcome['titleSize'] as num?)?.toDouble() ?? 20;
    return Material(
      color: background,
      child: LayoutBuilder(
        builder: (context, box) => Transform.translate(
          offset: const Offset(0, -20),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: min(box.maxWidth * .58, 240),
                  height: 84,
                  child: Image.asset(
                    dark
                        ? 'assets/branding/logo_oficial_ingeplus_dark.png'
                        : 'assets/branding/logo_oficial_ingeplus_light.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: 'Logo InGe+',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bienvenido a InGe+',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: title,
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 36,
                  height: 20,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _showActivity ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: _showActivity
                          ? FluentProgressRing(
                              size: 20,
                              strokeWidth: 2.5,
                              color: accent,
                              trackColor: accent.withValues(alpha: .18),
                              animate: widget.tokens.motionScale > 0,
                            )
                          : const SizedBox.shrink(),
                    ),
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

/// Port de FluentUI · FluProgressRing (modo indeterminado): el mismo recurso
/// que qml/Mobile/flowcore/FlowProgressRing.qml.
/// Origen: C:\Users\PC-02\Documents\calicatas\FluentUI-main.zip →
///   FluentUI-main/src/Qt6/imports/FluentUI/Controls/FluProgressRing.qml
/// Licencia: MIT, Copyright (c) 2023 zhuzichu (FluentUI-main/License).
/// Conserva: ciclo de 2000 ms; startAngle 0 → 450 → 1080 y sweepAngle
/// 0 → 180 → 0 en dos mitades lineales; arco desde startAngle − 90°,
/// extremos redondeados y pista circular de igual grosor.
class FluentProgressRing extends StatefulWidget {
  const FluentProgressRing({
    required this.color,
    required this.trackColor,
    this.size = 20,
    this.strokeWidth = 2.5,
    this.animate = true,
    super.key,
  });

  final Color color;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final bool animate;

  @override
  State<FluentProgressRing> createState() => _FluentProgressRingState();
}

class _FluentProgressRingState extends State<FluentProgressRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant FluentProgressRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _sync();
  }

  void _sync() {
    if (widget.animate) {
      _cycle.repeat();
    } else {
      _cycle
        ..stop()
        ..value = .25;
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _FluentRingPainter(
          _cycle,
          color: widget.color,
          trackColor: widget.trackColor,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    ),
  );
}

class _FluentRingPainter extends CustomPainter {
  _FluentRingPainter(
    this.cycle, {
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  }) : super(repaint: cycle);

  final Animation<double> cycle;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final t = cycle.value;
    final firstHalf = t < .5;
    final local = firstHalf ? t * 2 : (t - .5) * 2;
    final startAngle = firstHalf ? 450 * local : 450 + 630 * local;
    final sweepAngle = firstHalf ? 180 * local : 180 * (1 - local);
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - strokeWidth / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );
    if (sweepAngle <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      (startAngle - 90) * pi / 180,
      sweepAngle * pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _FluentRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _AuthAccount {
  const _AuthAccount({
    required this.id,
    required this.email,
    required this.name,
    required this.avatar,
  });

  final String id;
  final String email;
  final String name;
  final String avatar;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? 'IN' : value;
  }

  factory _AuthAccount.fromMap(Map<Object?, Object?> value) {
    final first = value['name']?.toString().trim() ?? '';
    final last = value['lastName']?.toString().trim() ?? '';
    final email = value['email']?.toString() ?? '';
    final fallback = email.contains('@')
        ? email.split('@').first
        : 'Cuenta InGe+';
    return _AuthAccount(
      id: value['id']?.toString() ?? '',
      email: email,
      name: '$first $last'.trim().isEmpty ? fallback : '$first $last'.trim(),
      avatar:
          value['avatarUrl']?.toString() ??
          value['avatarPath']?.toString() ??
          '',
    );
  }
}

class InGeAuthScreen extends StatefulWidget {
  const InGeAuthScreen({
    required this.tokens,
    required this.state,
    required this.biometricAvailable,
    required this.vaultReady,
    required this.vaultAccountId,
    required this.authenticateBiometric,
    super.key,
  });

  final HomeTokens tokens;
  final Map<String, dynamic> state;
  final bool biometricAvailable;
  final bool vaultReady;
  final String? vaultAccountId;
  final Future<bool> Function() authenticateBiometric;

  @override
  State<InGeAuthScreen> createState() => _InGeAuthScreenState();
}

class _InGeAuthScreenState extends State<InGeAuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _passwordMode = false;
  bool _passwordVisible = false;
  bool _remember = true;
  bool _localBusy = false;
  bool _automaticBiometricAttempted = false;
  String _localError = '';

  @override
  void initState() {
    super.initState();
    debugPrint('AUTH_LOGIN_WIDGET_MOUNTED');
    _scheduleAutomaticBiometric();
  }

  List<_AuthAccount> get accounts =>
      (widget.state['accounts'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (value) => _AuthAccount.fromMap(Map<Object?, Object?>.from(value)),
          )
          .where((account) => account.id.isNotEmpty)
          .toList();

  _AuthAccount? get knownAccount {
    final vaultId = widget.vaultAccountId;
    if (vaultId == null) return null;
    for (final account in accounts) {
      if (account.id == vaultId) return account;
    }
    return null;
  }

  bool get busy => widget.state['busy'] == true || _localBusy;
  String get error {
    final hostError = widget.state['error']?.toString() ?? '';
    return hostError.isNotEmpty ? hostError : _localError;
  }

  void _scheduleAutomaticBiometric() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _automaticBiometricAttempted || _passwordMode || busy) {
        return;
      }
      final account = knownAccount;
      if (!widget.vaultReady || account == null) {
        return;
      }
      _automaticBiometricAttempted = true;
      if (!widget.biometricAvailable) {
        setState(() {
          _email.text = account.email;
          _passwordMode = true;
          _localError =
              'La biometría no está disponible. Ingresa tu contraseña.';
        });
        return;
      }
      unawaited(_loginWithBiometric(automatic: true));
    });
  }

  @override
  void didUpdateWidget(covariant InGeAuthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state['busy'] == true && widget.state['busy'] != true) {
      _localBusy = false;
    }
    final nextError = widget.state['error']?.toString() ?? '';
    if (nextError.isNotEmpty && nextError != oldWidget.state['error']) {
      _localBusy = false;
      _localError = '';
      if (widget.state['biometricFailed'] == true) {
        final account = knownAccount;
        if (account != null && _email.text.isEmpty) _email.text = account.email;
        _passwordMode = true;
      }
    }
    _scheduleAutomaticBiometric();
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  Future<void> _request(Map<String, Object> request) async {
    try {
      await _host.invokeMethod<void>('authRequest', request);
    } on PlatformException {
      if (mounted) {
        setState(() {
          _localBusy = false;
          _localError = 'No se pudo comunicar con el servicio de acceso.';
        });
      }
    }
  }

  Future<void> _loginWithPassword() async {
    // Done/Iniciar sesión: sin teclado desde el primer instante, también si
    // la validación local rechaza el intento.
    FocusManager.instance.primaryFocus?.unfocus();
    final exactEmail = _email.text;
    final password = _password.text;
    if (exactEmail.trim().isEmpty || password.isEmpty) {
      await _request(<String, Object>{
        'type': 'clientError',
        'message': 'Ingresa tu correo y contraseña.',
      });
      return;
    }
    setState(() {
      _localBusy = true;
      _localError = '';
    });
    await _request(<String, Object>{
      'type': 'password',
      'email': exactEmail,
      'password': password,
      'remember': _remember,
    });
    // Se conserva mientras Supabase responde para que un error no obligue a
    // reescribirla. El controller se destruye junto con Auth tras el éxito.
  }

  Future<void> _loginWithBiometric({bool automatic = false}) async {
    final account = knownAccount;
    if (account == null || busy) return;
    setState(() {
      _localBusy = true;
      _localError = '';
    });
    final authenticated = await widget.authenticateBiometric();
    if (!mounted) return;
    if (!authenticated) {
      setState(() {
        _localBusy = false;
        _passwordMode = true;
        _email.text = account.email;
        _localError = automatic
            ? 'No se completó la verificación. Ingresa tu contraseña.'
            : '';
      });
      // Tras cerrar el diálogo biométrico no se enfoca ningún campo por su
      // cuenta (sin teclado fantasma); el usuario toca Contraseña.
      return;
    }
    await _request(<String, Object>{
      'type': 'biometric',
      'accountId': account.id,
    });
  }

  void _showPassword({_AuthAccount? account}) {
    if (account != null) _email.text = account.email;
    setState(() {
      _passwordMode = true;
      _localError = '';
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _passwordFocus.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = InGePalette(widget.tokens);
    final known = knownAccount;
    final showKnown = known != null && !_passwordMode;
    final accent = palette.accent;
    final imeVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    const onBackground = Color(0xd9ffffff);
    const fieldText = Color(0xf2ffffff);
    const fieldHint = Color(0xa8ffffff);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: IngemaBrand.deep,
      // Liquid Glass del Dock: una única captura de este fondo alimenta las
      // cápsulas de Correo, Contraseña e Iniciar sesión (InGeGlassSurface).
      body: InGeGlassBackdrop(
        name: 'auth',
        // Fondo animado (video INGEMA) con póster inmediato y tinte Deep/Navy.
        background: AuthVideoBackground(
          animate: !MediaQuery.disableAnimationsOf(context),
        ),
        child: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final dense = viewport.maxHeight < 820;
                final logoSpace = imeVisible
                    ? 86.0
                    : (viewport.maxHeight * .27).clamp(180.0, 240.0).toDouble();
                final logoSize = imeVisible ? 66.0 : 104.0;
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    10,
                    imeVisible ? 2 : 8,
                    10,
                    dense ? 6 : 10,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: viewport.maxHeight - (dense ? 8 : 18),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          height: logoSpace,
                          child: Center(
                            child: _AuthEntrance(
                              tokens: widget.tokens,
                              child: AnimatedContainer(
                                duration: InGeHomeMotion(
                                  widget.tokens,
                                ).duration(220),
                                curve: Curves.easeOutCubic,
                                width: logoSize,
                                height: logoSize,
                                child: Image.asset(
                                  'assets/branding/ingeplus_mark_light.png',
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                  semanticLabel: 'Logo InGe+',
                                ),
                              ),
                            ),
                          ),
                        ),
                        Center(
                          child: FractionallySizedBox(
                            widthFactor: .90,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 338),
                              child: _AuthEntrance(
                                tokens: widget.tokens,
                                delay: 55,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: dense ? 4 : 10,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Text(
                                        'InGe+',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: dense ? 30 : 32,
                                          height: 1.08,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -.48,
                                          shadows: const [
                                            Shadow(
                                              color: Color(0x70000000),
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: dense ? 16 : 20),
                                      AnimatedSwitcher(
                                        duration: InGeHomeMotion(
                                          widget.tokens,
                                        ).duration(220),
                                        switchInCurve: Curves.easeOutCubic,
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, .025),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            ),
                                        child: showKnown
                                            ? _KnownUserMethods(
                                                key: const ValueKey('known'),
                                                account: known,
                                                secondary: onBackground,
                                                accent: accent,
                                                busy: busy,
                                                error: error,
                                                dense: dense,
                                                onBiometric:
                                                    _loginWithBiometric,
                                                onPassword: () => _showPassword(
                                                  account: known,
                                                ),
                                                onChangeUser: () {
                                                  _email.clear();
                                                  setState(
                                                    () => _passwordMode = true,
                                                  );
                                                },
                                              )
                                            : _PasswordLoginForm(
                                                key: const ValueKey('password'),
                                                email: _email,
                                                password: _password,
                                                emailFocus: _emailFocus,
                                                passwordFocus: _passwordFocus,
                                                primary: fieldText,
                                                secondary: fieldHint,
                                                overlayText: onBackground,
                                                accent: accent,
                                                busy: busy,
                                                error: error,
                                                passwordVisible:
                                                    _passwordVisible,
                                                remember: _remember,
                                                dense: dense,
                                                onTogglePassword: () =>
                                                    setState(
                                                      () => _passwordVisible =
                                                          !_passwordVisible,
                                                    ),
                                                onToggleRemember: () =>
                                                    setState(
                                                      () => _remember =
                                                          !_remember,
                                                    ),
                                                onSubmit: _loginWithPassword,
                                                onBack: known == null
                                                    ? null
                                                    : () => setState(
                                                        () => _passwordMode =
                                                            false,
                                                      ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '© 2026 Ingema Consultores S.A.C.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .44),
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w400,
                            shadows: const [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 6,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: dense ? 8 : 14),
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

class _KnownUserMethods extends StatelessWidget {
  const _KnownUserMethods({
    required this.account,
    required this.secondary,
    required this.accent,
    required this.busy,
    required this.error,
    required this.dense,
    required this.onBiometric,
    required this.onPassword,
    required this.onChangeUser,
    super.key,
  });

  final _AuthAccount account;
  final Color secondary;
  final Color accent;
  final bool busy;
  final String error;
  final bool dense;
  final VoidCallback onBiometric;
  final VoidCallback onPassword;
  final VoidCallback onChangeUser;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: dense ? 48 : 56,
        height: dense ? 48 : 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.black, .32)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: .64),
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          account.initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: dense ? 16 : 18,
            fontWeight: IngemaBrand.semibold,
          ),
        ),
      ),
      SizedBox(height: dense ? 6 : 8),
      Text(
        account.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: secondary, fontSize: 13),
      ),
      SizedBox(height: dense ? 10 : 14),
      _AuthButton(
        label: busy ? 'Ingresando…' : 'INICIAR SESIÓN',
        iconName: 'fingerprint',
        color: accent,
        dense: dense,
        previewPill: true,
        loading: busy,
        enabled: !busy,
        onTap: onBiometric,
      ),
      if (error.isNotEmpty) ...[const SizedBox(height: 8), _AuthError(error)],
      SizedBox(height: dense ? 2 : 5),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: busy ? null : onPassword,
            style: TextButton.styleFrom(
              foregroundColor: secondary,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Usar contraseña'),
          ),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: secondary.withValues(alpha: .42),
              shape: BoxShape.circle,
            ),
          ),
          TextButton(
            onPressed: busy ? null : onChangeUser,
            style: TextButton.styleFrom(
              foregroundColor: secondary,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Cambiar usuario'),
          ),
        ],
      ),
    ],
  );
}

class _PasswordLoginForm extends StatelessWidget {
  const _PasswordLoginForm({
    required this.email,
    required this.password,
    required this.emailFocus,
    required this.passwordFocus,
    required this.primary,
    required this.secondary,
    required this.overlayText,
    required this.accent,
    required this.busy,
    required this.error,
    required this.passwordVisible,
    required this.remember,
    required this.dense,
    required this.onTogglePassword,
    required this.onToggleRemember,
    required this.onSubmit,
    this.onBack,
    super.key,
  });

  final TextEditingController email;
  final TextEditingController password;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final Color primary;
  final Color secondary;
  final Color overlayText;
  final Color accent;
  final bool busy;
  final String error;
  final bool passwordVisible;
  final bool remember;
  final bool dense;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleRemember;
  final VoidCallback onSubmit;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => AutofillGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null)
          TextButton.icon(
            onPressed: busy ? null : onBack,
            style: TextButton.styleFrom(
              foregroundColor: overlayText,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 34),
            ),
            icon: const PhosphorIcon('caret-left', size: 18),
            label: const Text('Volver'),
          ),
        _AuthTextField(
          controller: email,
          focusNode: emailFocus,
          primary: primary,
          secondary: secondary,
          accent: accent,
          label: 'Correo',
          iconName: 'envelope-simple',
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textCapitalization: TextCapitalization.none,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          textInputAction: TextInputAction.next,
          dense: dense,
          onSubmitted: (_) => passwordFocus.requestFocus(),
        ),
        SizedBox(height: dense ? 5 : 8),
        _AuthTextField(
          controller: password,
          focusNode: passwordFocus,
          primary: primary,
          secondary: secondary,
          accent: accent,
          label: 'Contraseña',
          iconName: 'lock-key',
          enabled: !busy,
          obscureText: !passwordVisible,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          dense: dense,
          onSubmitted: (_) => onSubmit(),
          trailing: IconButton(
            tooltip: passwordVisible
                ? 'Ocultar contraseña'
                : 'Mostrar contraseña',
            onPressed: busy ? null : onTogglePassword,
            icon: PhosphorIcon(
              passwordVisible ? 'eye-slash' : 'eye',
              color: secondary,
              size: 19,
            ),
          ),
        ),
        SizedBox(height: dense ? 1 : 4),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: busy ? null : onToggleRemember,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: dense ? 4 : 5),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: remember ? accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: remember ? accent : overlayText),
                  ),
                  child: remember
                      ? const PhosphorIcon(
                          'check',
                          color: Colors.white,
                          size: 14,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  'Recordar esta cuenta',
                  style: TextStyle(color: overlayText, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (error.isNotEmpty) ...[const SizedBox(height: 8), _AuthError(error)],
        SizedBox(height: dense ? 5 : 9),
        _AuthButton(
          label: busy ? 'Ingresando…' : 'INICIAR SESIÓN',
          iconName: 'arrow-right',
          color: accent,
          dense: dense,
          previewPill: true,
          loading: busy,
          enabled: !busy,
          onTap: onSubmit,
        ),
      ],
    ),
  );
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.focusNode,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.label,
    required this.iconName,
    required this.enabled,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.autofillHints,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.trailing,
    this.dense = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Color primary;
  final Color secondary;
  final Color accent;
  final String label;
  final String iconName;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool autocorrect;
  final bool enableSuggestions;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;
  final bool dense;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: focusNode,
    builder: (context, _) {
      final focused = focusNode.hasFocus;
      // Material: Liquid Glass del Dock (cápsula principal: frost 4.5). Foco
      // = misma intensificación que la lente seleccionada del Dock (1.2);
      // deshabilitado = menos contraste sin perder legibilidad.
      final targetStrength = !enabled ? .8 : (focused ? 1.2 : 1.0);
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: targetStrength),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        builder: (context, strength, child) => InGeGlassSurface(
          surfaceName: label == 'Correo' ? 'auth-email' : 'auth-password',
          cornerRadius: 29,
          strength: strength,
          frost: 4.5,
          child: child!,
        ),
        child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: EdgeInsets.symmetric(horizontal: dense ? 14 : 16),
            child: Row(
              children: [
                PhosphorIcon(
                  iconName,
                  color: focused ? Colors.white : secondary,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    keyboardType: keyboardType,
                    textCapitalization: textCapitalization,
                    autocorrect: autocorrect,
                    enableSuggestions: enableSuggestions,
                    autofillHints: autofillHints,
                    textInputAction: textInputAction,
                    obscureText: obscureText,
                    onSubmitted: onSubmitted,
                    style: TextStyle(color: primary, fontSize: 14),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.transparent,
                      hintText: label,
                      hintStyle: TextStyle(color: secondary, fontSize: 13.5),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      isDense: true,
                    ),
                  ),
                ),
                // Acción propia del campo (mostrar contraseña): no cuenta como
                // toque fuera, así no se cierra el teclado mientras se escribe.
                if (trailing != null) TextFieldTapRegion(child: trailing!),
              ],
            ),
          ),
      );
    },
  );
}

class _AuthButton extends StatefulWidget {
  const _AuthButton({
    required this.label,
    required this.iconName,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.dense = false,
    this.previewPill = false,
    this.loading = false,
  });

  final String label;
  final String iconName;
  final Color color;
  final bool dense;
  final bool previewPill;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) =>
      widget.previewPill ? _buildGlass(context) : _buildSolid(context);

  // Variante enfatizada del MISMO Liquid Glass del Dock (parámetros de la
  // lente seleccionada: strength 1.2 · lens · frost 2.5–3 · magnify). No es
  // una pastilla sólida: la fotografía sigue refractándose a través.
  Widget _buildGlass(BuildContext context) {
    final strength = !widget.enabled ? .85 : (pressed ? 1.35 : 1.2);
    return AnimatedScale(
      scale: pressed ? .985 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => pressed = true) : null,
        onTapCancel: widget.enabled
            ? () => setState(() => pressed = false)
            : null,
        onTapUp: widget.enabled
            ? (_) {
                setState(() => pressed = false);
                widget.onTap();
              }
            : null,
        child: AnimatedOpacity(
          // Deshabilitado/cargando: menos contraste, el vidrio se mantiene.
          opacity: widget.enabled ? 1 : (widget.loading ? .82 : .52),
          duration: const Duration(milliseconds: 160),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: strength),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => InGeGlassSurface(
                surfaceName: 'auth-login',
                cornerRadius: 29,
                strength: value,
                lens: 1.6,
                frost: 3,
                magnify: .03,
                child: child!,
              ),
              child: SizedBox(
                width: double.infinity,
                height: widget.dense ? 48 : 50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    else
                      PhosphorIcon(
                        widget.iconName,
                        size: 18,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 9),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: .55,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSolid(BuildContext context) => AnimatedScale(
    scale: pressed ? .97 : 1,
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    child: GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => pressed = true) : null,
      onTapCancel: widget.enabled
          ? () => setState(() => pressed = false)
          : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => pressed = false);
              widget.onTap();
            }
          : null,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : .52,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: double.infinity,
          height: widget.previewPill
              ? (widget.dense ? 48 : 50)
              : (widget.dense ? 52 : 54),
          margin: widget.previewPill
              ? const EdgeInsets.symmetric(horizontal: 8)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: widget.previewPill ? null : widget.color,
            gradient: widget.previewPill
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(
                        IngemaBrand.navy,
                        widget.color,
                        .18,
                      )!.withValues(alpha: .76),
                      IngemaBrand.deep.withValues(alpha: .65),
                      IngemaBrand.deepShade.withValues(alpha: .80),
                    ],
                    stops: const [0, .48, 1],
                  )
                : null,
            borderRadius: BorderRadius.circular(widget.previewPill ? 29 : 20),
            border: Border.all(
              color: widget.previewPill
                  ? Color.lerp(
                      Colors.white,
                      widget.color,
                      .20,
                    )!.withValues(alpha: .54)
                  : widget.color,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.previewPill
                    ? const Color(0x28000000)
                    : widget.color.withValues(alpha: .20),
                blurRadius: widget.previewPill ? 10 : 12,
                offset: Offset(0, widget.previewPill ? 3 : 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              else
                PhosphorIcon(
                  widget.iconName,
                  size: widget.previewPill ? 18 : 19,
                  color: Colors.white,
                ),
              const SizedBox(width: 9),
              Text(
                widget.label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: widget.previewPill ? 13 : 13.5,
                  letterSpacing: widget.previewPill ? .55 : .25,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0x18dc3545),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x44dc3545)),
    ),
    child: Text(
      message,
      style: const TextStyle(
        color: Color(0xffc74750),
        fontSize: 12,
        height: 1.25,
      ),
    ),
  );
}

class _AuthEntrance extends StatefulWidget {
  const _AuthEntrance({
    required this.tokens,
    required this.child,
    this.delay = 0,
  });
  final HomeTokens tokens;
  final Widget child;
  final int delay;

  @override
  State<_AuthEntrance> createState() => _AuthEntranceState();
}

class _AuthEntranceState extends State<_AuthEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    final motion = InGeHomeMotion(widget.tokens);
    _controller = AnimationController(
      vsync: this,
      duration: motion.duration(320),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: InGeHomeMotion.curve,
    );
    if (widget.tokens.motionScale <= 0) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(motion.duration(widget.delay), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, .035),
        end: Offset.zero,
      ).animate(_animation),
      child: widget.child,
    ),
  );
}

class InGeSecurityScreen extends StatefulWidget {
  const InGeSecurityScreen({
    required this.tokens,
    required this.state,
    required this.biometricAvailable,
    required this.vaultReady,
    required this.vaultAccountId,
    required this.enableVault,
    required this.disableVault,
    super.key,
  });

  final HomeTokens tokens;
  final Map<String, dynamic> state;
  final bool biometricAvailable;
  final bool vaultReady;
  final String? vaultAccountId;
  final Future<bool> Function(String accountId) enableVault;
  final Future<void> Function() disableVault;

  @override
  State<InGeSecurityScreen> createState() => _InGeSecurityScreenState();
}

class _InGeSecurityScreenState extends State<InGeSecurityScreen> {
  bool busy = false;

  String get accountId => widget.state['currentAccountId']?.toString() ?? '';
  bool get enabled => widget.vaultAccountId != null;
  String get status => enabled
      ? (widget.biometricAvailable
            ? 'Activado'
            : 'Activado · biometría no disponible')
      : (widget.biometricAvailable ? 'Disponible' : 'No disponible');

  Future<void> _toggle() async {
    if (busy || (!enabled && !widget.biometricAvailable)) return;
    setState(() => busy = true);
    if (enabled) {
      await widget.disableVault();
    } else {
      await widget.enableVault(accountId);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = InGePalette(widget.tokens);
    final primary = palette.textPrimary;
    final secondary = palette.textSecondary;
    final accent = palette.accent;
    return Scaffold(
      backgroundColor: const Color(0x77000000),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 480),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: palette.glassRegular,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: widget.tokens.idleGlass
                      ? palette.glassBorder
                      : palette.border,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 32,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seguridad',
                              style: TextStyle(
                                color: primary,
                                fontSize: 24,
                                fontWeight: IngemaBrand.semibold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Acceso a este dispositivo',
                              style: TextStyle(
                                color: secondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => _host.invokeMethod<void>(
                          'authRequest',
                          <String, Object>{'type': 'closeSecurity'},
                        ),
                        icon: PhosphorIcon('x', color: primary, size: 22),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(17),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: accent.withValues(alpha: .20)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: PhosphorIcon(
                            'fingerprint',
                            color: accent,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ingreso biométrico',
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 16,
                                  fontWeight: IngemaBrand.semibold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                status,
                                style: TextStyle(
                                  color: enabled ? accent : secondary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'InGe+ no guarda tu huella ni datos faciales. Android verifica tu identidad y el vault del dispositivo conserva únicamente un vínculo de sesión cifrado.',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12.5,
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _AuthButton(
                    label: busy
                        ? 'Verificando…'
                        : enabled
                        ? 'Desactivar ingreso biométrico'
                        : 'Activar ingreso biométrico',
                    iconName: enabled ? 'lock-key' : 'fingerprint',
                    color: enabled ? const Color(0xff9a454b) : accent,
                    enabled:
                        !busy &&
                        (enabled ||
                            (widget.biometricAvailable &&
                                accountId.isNotEmpty)),
                    onTap: _toggle,
                  ),
                  if (!widget.biometricAvailable) ...[
                    const SizedBox(height: 12),
                    const _AuthError(
                      'Este dispositivo no tiene biometría disponible o configurada.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InGeHomeScreen extends StatefulWidget {
  const InGeHomeScreen({required this.tokens, required this.state, super.key});

  final HomeTokens tokens;
  final Map<String, dynamic> state;

  @override
  State<InGeHomeScreen> createState() => _InGeHomeScreenState();
}

class _InGeHomeScreenState extends State<InGeHomeScreen> {
  final ScrollController _scroll = ScrollController();

  InGeHomeMotion get motion => InGeHomeMotion(widget.tokens);

  Map<String, dynamic> get projection {
    final value = widget.state['homeProjection'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  Map<String, dynamic> get headerProjection {
    final value = projection['header'];
    return value is Map ? Map<String, dynamic>.from(value) : const {};
  }

  Future<void> _action(String action, {bool quick = false}) async {
    // INGE_PERF_120HZ_V1: navegar inmediatamente; el feedback visual sigue en la tarjeta.
    if (!mounted) return;
    await _host.invokeMethod<void>(quick ? 'quickAction' : 'navigate', {
      'action': action,
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.tokens.dark;
    final palette = InGeHomePalette(widget.tokens);
    final background = palette.backgroundPrimary;
    final primary = palette.textPrimary;
    final secondary = palette.textSecondary;
    final safePadding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.tokens.idleGlass
                      ? <Color>[
                          Color.lerp(
                            palette.backgroundSecondary,
                            palette.accent,
                            dark ? .08 : .11,
                          )!,
                          palette.backgroundSecondary,
                          palette.backgroundPrimary,
                        ]
                      : <Color>[
                          palette.backgroundSecondary,
                          palette.backgroundPrimary,
                          palette.backgroundPrimary,
                        ],
                  stops: const <double>[0, .42, 1],
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: ScrollConfiguration(
                  behavior: const _HomeScrollBehavior(),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      16,
                      safePadding.top + 86,
                      16,
                      safePadding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Reveal(
                          motion: motion,
                          delay: 0,
                          child: _MainGrid(
                            tokens: widget.tokens,
                            motion: motion,
                            onCalicatas: () => _action('calicatas'),
                            onDocuments: () => _action('documents'),
                            onEarth: () => _action('earth'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Reveal(
                          motion: motion,
                          delay: 40,
                          child: SizedBox(
                            height: 152,
                            child: _HomeCard(
                              tokens: widget.tokens,
                              motion: motion,
                              onTap: () => _action('renditions'),
                              padding: const EdgeInsets.fromLTRB(
                                15,
                                14,
                                12,
                                12,
                              ),
                              child: const _RenditionsCard(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Reveal(
                          motion: motion,
                          delay: 60,
                          child: _QuickActions(
                            tokens: widget.tokens,
                            primary: primary,
                            motion: motion,
                            onAction: (value) => _action(value, quick: true),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Reveal(
                          motion: motion,
                          delay: 120,
                          child: _RecentActivity(
                            tokens: widget.tokens,
                            primary: primary,
                            secondary: secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          _HomeHeaderProjection(
            tokens: widget.tokens,
            name: headerProjection['name']?.toString() ?? 'InGe+',
            role: headerProjection['role']?.toString() ?? 'USUARIO',
            avatar: headerProjection['avatar']?.toString() ?? '',
            onProfile: () => _action('profile'),
            onSearch: () => _action('search'),
            onNotifications: () => _action('notifications'),
          ),
        ],
      ),
    );
  }
}

class _MainGrid extends StatelessWidget {
  const _MainGrid({
    required this.tokens,
    required this.motion,
    required this.onCalicatas,
    required this.onDocuments,
    required this.onEarth,
  });

  final HomeTokens tokens;
  final InGeHomeMotion motion;
  final VoidCallback onCalicatas;
  final VoidCallback onDocuments;
  final VoidCallback onEarth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final dark = tokens.dark;
      final height = constraints.maxWidth < 390 ? 378.0 : 396.0;
      return SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 57,
              child: _HomeCard(
                tokens: tokens,
                motion: motion,
                onTap: onCalicatas,
                padding: const EdgeInsets.fromLTRB(15, 16, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _CardIdentity(
                      iconName: 'mountains',
                      color: IngemaBrand.green,
                    ),
                    const SizedBox(height: 11),
                    const _CardTitle('Calicatas'),
                    const SizedBox(height: 6),
                    const _CardDescription(
                      'Crea, edita y administra registros geotécnicos de campo.',
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _StratigraphyPreview(dark: dark),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 43,
              child: Column(
                children: [
                  Expanded(
                    child: _HomeCard(
                      tokens: tokens,
                      motion: motion,
                      onTap: onDocuments,
                      padding: const EdgeInsets.fromLTRB(13, 14, 10, 10),
                      child: const _CompactCard(
                        iconName: 'file-text',
                        iconColor: IngemaBrand.blue,
                        title: 'Documentos',
                        description: 'Organiza informes y archivos técnicos.',
                        visual: _DocumentVisual(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _HomeCard(
                      tokens: tokens,
                      motion: motion,
                      onTap: onEarth,
                      padding: const EdgeInsets.fromLTRB(13, 14, 10, 10),
                      child: const _CompactCard(
                        iconName: 'globe-hemisphere-west',
                        iconColor: IngemaBrand.navy,
                        title: 'InGe Earth',
                        description: 'Explora el territorio y tus ubicaciones.',
                        visual: _TopoVisual(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _RenditionsCard extends StatelessWidget {
  const _RenditionsCard();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Row(
        children: [
          const Expanded(
            flex: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CardIdentity(iconName: 'receipt', color: IngemaBrand.deep),
                SizedBox(height: 8),
                _CardTitle('Rendición de cuentas'),
                SizedBox(height: 4),
                _CardDescription(
                  'Registra periodos, gastos y borradores disponibles sin conexión.',
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(flex: 42, child: _DocumentVisual()),
        ],
      ),
    ],
  );
}

class _HomeHeaderProjection extends StatelessWidget {
  const _HomeHeaderProjection({
    required this.tokens,
    required this.name,
    required this.role,
    required this.avatar,
    required this.onProfile,
    required this.onSearch,
    required this.onNotifications,
  });

  final HomeTokens tokens;
  final String name;
  final String role;
  final String avatar;
  final VoidCallback onProfile;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final palette = InGeHomePalette(tokens);
    final safeTop = MediaQuery.viewPaddingOf(context).top;
    final cleanName = name.trim().isEmpty ? 'InGe+' : name.trim();
    final cleanRole = role.trim().isEmpty ? 'USUARIO' : role.trim();
    final initials = cleanName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final avatarUri = Uri.tryParse(avatar);
    final ImageProvider? avatarImage =
        avatarUri != null &&
            (avatarUri.scheme == 'https' || avatarUri.scheme == 'http')
        ? NetworkImage(avatar)
        : null;

    return Positioned(
      top: safeTop + 10,
      left: 14,
      right: 14,
      height: 50,
      child: Row(
        children: [
          SizedBox(
            width: cleanRole == 'DEV' ? 190 : 160,
            height: 50,
            child: _HomeGlassPanel(
              tokens: tokens,
              radius: 25,
              elevation: 1,
              forceOpaque: true,
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onProfile,
                  borderRadius: BorderRadius.circular(25),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 5, 6, 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cleanName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                cleanRole,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 9),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: palette.accent.withValues(
                            alpha: .14,
                          ),
                          backgroundImage: avatarImage,
                          child: avatarImage == null
                              ? Text(
                                  initials.isEmpty ? 'IN' : initials,
                                  style: TextStyle(
                                    color: palette.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          _HomeHeaderButton(
            tokens: tokens,
            iconName: 'search',
            label: 'Buscar',
            onTap: onSearch,
          ),
          const SizedBox(width: 8),
          _HomeHeaderButton(
            tokens: tokens,
            iconName: 'notifications',
            label: 'Notificaciones',
            onTap: onNotifications,
          ),
        ],
      ),
    );
  }
}

class _HomeHeaderButton extends StatelessWidget {
  const _HomeHeaderButton({
    required this.tokens,
    required this.iconName,
    required this.label,
    required this.onTap,
  });

  final HomeTokens tokens;
  final String iconName;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = InGeHomePalette(tokens);
    return SizedBox(
      width: 50,
      height: 50,
      child: _HomeGlassPanel(
        tokens: tokens,
        radius: 25,
        elevation: 1,
        forceOpaque: true,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(25),
            child: Semantics(
              button: true,
              label: label,
              child: Center(
                child: CustomPaint(
                  size: const Size(24, 24),
                  painter: _HomeHeaderGlyphPainter(
                    kind: iconName,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeHeaderGlyphPainter extends CustomPainter {
  const _HomeHeaderGlyphPainter({required this.kind, required this.color});

  final String kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    canvas.save();
    canvas.scale(sx, sy);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (kind == 'search') {
      canvas.drawCircle(const Offset(10.2, 10.2), 6.4, stroke);
      canvas.drawLine(
        const Offset(14.9, 14.9),
        const Offset(20.2, 20.2),
        stroke,
      );
    } else {
      final bell = Path()
        ..moveTo(6.4, 16.7)
        ..cubicTo(7.6, 15.4, 8.0, 14.1, 8.0, 11.4)
        ..cubicTo(8.0, 8.4, 9.6, 6.3, 12.0, 6.3)
        ..cubicTo(14.4, 6.3, 16.0, 8.4, 16.0, 11.4)
        ..cubicTo(16.0, 14.1, 16.4, 15.4, 17.6, 16.7)
        ..lineTo(6.4, 16.7);

      canvas.drawPath(bell, stroke);
      canvas.drawLine(
        const Offset(10.2, 19.0),
        const Offset(13.8, 19.0),
        stroke,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HomeHeaderGlyphPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}

class _StratigraphyPreview extends StatelessWidget {
  const _StratigraphyPreview({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _StratigraphyPainter(dark),
      child: const SizedBox.expand(),
    ),
  );
}

class _StratigraphyPainter extends CustomPainter {
  const _StratigraphyPainter(this.dark);

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final bounds = Offset.zero & size;
    final background = Paint()
      ..color = dark ? const Color(0xff112431) : const Color(0xffeef4ef);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(16)),
      background,
    );

    final left = size.width * .12;
    final right = size.width * .88;
    final top = size.height * .13;
    final bottom = size.height * .86;
    final depth = size.width * .10;

    final layerColors = dark
        ? const [
            Color(0xff355c4d),
            Color(0xff5f7451),
            Color(0xff826c4c),
            Color(0xff5c544d),
          ]
        : const [
            Color(0xff8ab79a),
            Color(0xffb8c979),
            Color(0xffcaa06a),
            Color(0xff91847b),
          ];

    final heights = <double>[.18, .24, .27, .31];
    var y = top;
    for (var index = 0; index < layerColors.length; ++index) {
      final nextY = index == layerColors.length - 1
          ? bottom
          : y + (bottom - top) * heights[index];

      final front = Path()
        ..moveTo(left, y)
        ..lineTo(right - depth, y)
        ..lineTo(right - depth, nextY)
        ..lineTo(left, nextY)
        ..close();
      canvas.drawPath(front, Paint()..color = layerColors[index]);

      final side = Path()
        ..moveTo(right - depth, y)
        ..lineTo(right, y - depth * .42)
        ..lineTo(right, nextY - depth * .42)
        ..lineTo(right - depth, nextY)
        ..close();
      canvas.drawPath(
        side,
        Paint()..color = Color.lerp(layerColors[index], Colors.black, .14)!,
      );

      y = nextY;
    }

    final topFace = Path()
      ..moveTo(left, top)
      ..lineTo(left + depth, top - depth * .42)
      ..lineTo(right, top - depth * .42)
      ..lineTo(right - depth, top)
      ..close();
    canvas.drawPath(
      topFace,
      Paint()..color = dark ? const Color(0xff4b7560) : const Color(0xffa8c9ac),
    );

    final outline = Paint()
      ..color = dark ? const Color(0x665f8f7a) : const Color(0x554a7161)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(topFace, outline);
  }

  @override
  bool shouldRepaint(covariant _StratigraphyPainter oldDelegate) =>
      oldDelegate.dark != dark;
}

class _HomeCard extends StatefulWidget {
  const _HomeCard({
    required this.tokens,
    required this.motion,
    required this.onTap,
    required this.child,
    required this.padding,
  });

  final HomeTokens tokens;
  final InGeHomeMotion motion;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<_HomeCard> createState() => _HomeCardState();
}

class _HomeCardState extends State<_HomeCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? .976 : 1,
      duration: widget.motion.duration(_pressed ? 85 : 180),
      curve: InGeHomeMotion.curve,
      child: _HomeGlassPanel(
        tokens: widget.tokens,
        radius: 24,
        pressed: _pressed,
        elevation: 2,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _HomeGlassPanel extends StatelessWidget {
  const _HomeGlassPanel({
    required this.tokens,
    required this.child,
    required this.radius,
    this.pressed = false,
    this.selected = false,
    this.elevation = 1,
    this.forceOpaque = false,
  });

  final HomeTokens tokens;
  final Widget child;
  final double radius;
  final bool pressed;
  final bool selected;
  final int elevation;
  final bool forceOpaque;

  @override
  Widget build(BuildContext context) {
    final palette = InGeHomePalette(tokens);
    final glass = tokens.idleGlass && !forceOpaque;
    final borderRadius = BorderRadius.circular(radius);
    final solidTop =
        (selected
                ? Color.lerp(palette.surfaceElevated, palette.accent, .16)!
                : palette.surfaceElevated)
            .withValues(alpha: 1);
    final solidBottom =
        (pressed
                ? Color.lerp(palette.surfacePrimary, palette.textPrimary, .07)!
                : palette.surfacePrimary)
            .withValues(alpha: 1);
    final glassBase = palette.glassRegular.withValues(
      alpha: palette.dark ? .66 : .72,
    );

    final material = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: glass
              ? <Color>[
                  Colors.white.withValues(alpha: palette.dark ? .17 : .58),
                  selected
                      ? Color.lerp(glassBase, palette.accent, .22)!
                      : glassBase,
                  palette.dark
                      ? IngemaBrand.deep.withValues(alpha: .56)
                      : const Color(0x8ff4fafb),
                ]
              : <Color>[solidTop, solidBottom],
          stops: glass ? const <double>[0, .34, 1] : const <double>[0, 1],
        ),
        border: Border.all(
          color: glass
              ? (selected
                    ? Color.lerp(palette.glassBorder, palette.accent, .44)!
                    : palette.glassBorder)
              : palette.border,
          width: selected ? 1.35 : 1,
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (glass)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius - 1.5),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: palette.dark ? .09 : .34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (glass)
            Positioned(
              left: radius * .72,
              right: radius * .72,
              top: 1,
              height: 1.3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(1),
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.transparent,
                        Colors.white.withValues(
                          alpha: palette.dark ? .45 : .92,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );

    // Keep the Liquid Glass material deterministic on embedded Android.
    // Backdrop sampling under animated opacity created oversized Impeller
    // filter layers; tint, rim, highlight and elevation remain active.
    final filtered = material;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: elevation <= 0
              ? const <BoxShadow>[]
              : <BoxShadow>[
                  BoxShadow(
                    color: palette.dark
                        ? const Color(0x72000000)
                        : const Color(0x30071a24),
                    blurRadius: pressed ? 9 : (glass ? 25 : 18),
                    spreadRadius: -4,
                    offset: Offset(0, pressed ? 3 : 9),
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

class _CardIdentity extends StatelessWidget {
  const _CardIdentity({required this.iconName, required this.color});

  final String iconName;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(11),
    ),
    child: PhosphorIcon(iconName, color: color, size: 20),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: 17,
      letterSpacing: -.35,
    ),
  );
}

class _CardDescription extends StatelessWidget {
  const _CardDescription(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 11.6,
      height: 1.28,
      fontWeight: FontWeight.w400,
    ),
  );
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({
    required this.iconName,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.visual,
  });

  final String iconName;
  final Color iconColor;
  final String title;
  final String description;
  final Widget visual;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardIdentity(iconName: iconName, color: iconColor),
          const SizedBox(height: 8),
          _CardTitle(title),
          const SizedBox(height: 4),
          _CardDescription(description),
          const Spacer(),
          SizedBox(height: 47, width: double.infinity, child: visual),
        ],
      ),
    ],
  );
}

class _DocumentVisual extends StatelessWidget {
  const _DocumentVisual();

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DocumentPainter());
}

class _DocumentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final shadow = Paint()..color = const Color(0x180d2b3b);
    final paper = Paint()..color = const Color(0xffeaf2f6);
    final ink = Paint()
      ..color = const Color(0xff4f7891)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * .12, 2, size.width * .58, size.height - 5),
      const Radius.circular(7),
    );
    canvas.drawRRect(rect.shift(const Offset(3, 3)), shadow);
    canvas.drawRRect(rect, paper);
    for (var i = 0; i < 3; i++) {
      final y = 14.0 + i * 8;
      canvas.drawLine(
        Offset(size.width * .22, y),
        Offset(size.width * (.58 - i * .04), y),
        ink,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .55),
      14,
      Paint()..color = const Color(0xffc9dce6),
    );
    canvas.drawLine(
      Offset(size.width * .68, size.height * .55),
      Offset(size.width * .76, size.height * .55),
      ink,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopoVisual extends StatelessWidget {
  const _TopoVisual();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _TopoPainter());
}

class _TopoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff77a797)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 4; i++) {
      final inset = i * 5.0;
      final path = Path()
        ..moveTo(inset, size.height * (.72 - i * .08))
        ..cubicTo(
          size.width * .23,
          -4 + inset,
          size.width * .55,
          size.height + 2 - inset,
          size.width,
          size.height * (.25 + i * .06),
        );
      canvas.drawPath(
        path,
        paint
          ..color = Color.lerp(
            const Color(0xffb8d5cb),
            const Color(0xff397b69),
            i / 3,
          )!,
      );
    }
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .38),
      5.5,
      Paint()..color = const Color(0xff277d68),
    );
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .38),
      10,
      Paint()..color = const Color(0x24277d68),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.tokens,
    required this.primary,
    required this.motion,
    required this.onAction,
  });

  final HomeTokens tokens;
  final Color primary;
  final InGeHomeMotion motion;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Accesos rápidos',
        style: TextStyle(
          color: primary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -.35,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _QuickItem(
            tokens: tokens,
            motion: motion,
            iconName: 'plus',
            label: 'Nuevo\nproyecto',
            onTap: () => onAction('newProject'),
          ),
          const SizedBox(width: 10),
          _QuickItem(
            tokens: tokens,
            motion: motion,
            iconName: 'arrows-clockwise',
            label: 'Sincronizar',
            onTap: () => onAction('sync'),
          ),
          const SizedBox(width: 10),
          _QuickItem(
            tokens: tokens,
            motion: motion,
            iconName: 'squares-four',
            label: 'Plantillas',
            onTap: () => onAction('templates'),
          ),
        ],
      ),
    ],
  );
}

class _QuickItem extends StatefulWidget {
  const _QuickItem({
    required this.tokens,
    required this.motion,
    required this.iconName,
    required this.label,
    required this.onTap,
  });

  final HomeTokens tokens;
  final InGeHomeMotion motion;
  final String iconName;
  final String label;
  final VoidCallback onTap;

  @override
  State<_QuickItem> createState() => _QuickItemState();
}

class _QuickItemState extends State<_QuickItem> {
  bool pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = InGeHomePalette(widget.tokens);
    return Expanded(
      child: AnimatedScale(
        scale: pressed ? .985 : 1,
        duration: widget.motion.duration(110),
        child: SizedBox(
          height: 82,
          child: _HomeGlassPanel(
            tokens: widget.tokens,
            radius: 21,
            pressed: pressed,
            elevation: 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(21),
                onHighlightChanged: (value) => setState(() => pressed = value),
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PhosphorIcon(
                        widget.iconName,
                        size: 22,
                        color: palette.dark
                            ? IngemaBrand.greenTint
                            : IngemaBrand.green,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(
                          fontSize: 11.2,
                          height: 1.05,
                          fontWeight: FontWeight.w600,
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
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.tokens,
    required this.primary,
    required this.secondary,
  });

  final HomeTokens tokens;
  final Color primary;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final dark = tokens.dark;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Actividad reciente',
                style: TextStyle(
                  color: primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.35,
                ),
              ),
            ),
            Text(
              'Ver todo',
              style: TextStyle(
                color: dark ? IngemaBrand.blueTint : IngemaBrand.blue,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _HomeGlassPanel(
            tokens: tokens,
            radius: 22,
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: IngemaBrand.green.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const PhosphorIcon(
                      'clock-counter-clockwise',
                      color: IngemaBrand.green,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aún no hay actividad',
                          style: TextStyle(
                            color: primary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Tus proyectos y documentos recientes aparecerán aquí.',
                          style: TextStyle(
                            color: secondary,
                            fontSize: 11.6,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Reveal extends StatefulWidget {
  const _Reveal({
    required this.motion,
    required this.delay,
    required this.child,
  });

  final InGeHomeMotion motion;
  final int delay;
  final Widget child;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final Animation<double> opacity;
  late final Animation<Offset> slide;
  late final Animation<double> scale;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: widget.motion.duration(240),
    );
    final curved = CurvedAnimation(
      parent: controller,
      curve: InGeHomeMotion.curve,
    );
    opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    slide = Tween<Offset>(
      begin: const Offset(0, .045),
      end: Offset.zero,
    ).animate(curved);
    scale = Tween<double>(begin: .985, end: 1).animate(curved);
    if (widget.motion.tokens.motionScale <= 0) {
      controller.value = 1;
    } else {
      Future<void>.delayed(widget.motion.duration(widget.delay), () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: opacity,
    child: SlideTransition(
      position: slide,
      child: ScaleTransition(scale: scale, child: widget.child),
    ),
  );
}

class _HomeScrollBehavior extends ScrollBehavior {
  const _HomeScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
