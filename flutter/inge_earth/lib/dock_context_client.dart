import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One semantic action published to the host dock. No geometry, no theme:
/// the single QML dock owned by the host decides how it is represented.
class DockAction {
  const DockAction(
    this.id,
    this.label,
    this.icon,
    this.command, {
    this.enabled = true,
    this.visible = true,
    this.selected = false,
    this.badge = '',
    this.priority = 100,
    this.repeatable = false,
  });

  final String id;
  final String label;
  final String icon;
  final String command;
  final bool enabled;
  final bool visible;
  final bool selected;
  final String badge;
  final int priority;
  final bool repeatable;

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'label': label,
    'icon': icon,
    'command': command,
    'enabled': enabled,
    'visible': visible,
    'selected': selected,
    'badge': badge,
    'priority': priority,
    'repeatable': repeatable,
  };
}

typedef DockCommandHandler = FutureOr<void> Function(String command);

/// Flutter adapter for the host dock context. It publishes small snapshots on
/// a dedicated channel (never through auth/home state) and executes commands
/// routed back by the host for the owner and context it last published.
class DockContextClient {
  DockContextClient._() {
    _channel.setMethodCallHandler(_handleHostCall);
  }

  static final DockContextClient instance = DockContextClient._();
  static const MethodChannel _channel = MethodChannel('inge.dock/context');

  final Map<String, DockCommandHandler> _handlers = <String, DockCommandHandler>{};
  final Map<String, String> _contexts = <String, String>{};
  final Map<String, String> _payloads = <String, String>{};

  void publish(
    String ownerId,
    String contextId,
    List<DockAction> actions,
    DockCommandHandler handler,
  ) {
    _handlers[ownerId] = handler;
    final payload = jsonEncode(<String, Object>{
      'ownerId': ownerId,
      'contextId': contextId,
      'actions': [for (final action in actions) action.toJson()],
    });
    if (_payloads[ownerId] == payload) return;
    _payloads[ownerId] = payload;
    _contexts[ownerId] = contextId;
    unawaited(_invoke('publish', payload));
    // Entry: one capture once the frame is on screen, one refined capture
    // after images/fonts settle. Nothing else while the surface is idle.
    _backdropOwner = ownerId;
    requestBackdrop(const <int>[160, 1200]);
  }

  /// Withdraws the context this client published for [ownerId]. Idempotent:
  /// the host is only told when a snapshot of this owner is live, so repeated
  /// calls never end another owner's handoff. A command routed afterwards to
  /// this owner finds no handler/context and is dropped.
  void clear(String ownerId) {
    _handlers.remove(ownerId);
    _contexts.remove(ownerId);
    final wasPublished = _payloads.remove(ownerId) != null;
    // Only this owner's pending captures are cancelled.
    if (_backdropOwner == ownerId) {
      _cancelBackdrop();
      _backdropOwner = '';
    }
    if (wasPublished) unawaited(_invoke('clear', ownerId));
  }

  /// Host -> Flutter: {"ownerId","contextId","command","dispatchId",...}.
  Future<void> _handleHostCall(MethodCall call) async {
    if (call.method != 'command') return;
    final Object? arguments = call.arguments;
    if (arguments is! String) return;
    Object? decoded;
    try {
      decoded = jsonDecode(arguments);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final Map<Object?, Object?> payload = decoded;
    String field(String key) {
      final Object? value = payload[key];
      return value is String ? value : '';
    }

    final ownerId = field('ownerId');
    final contextId = field('contextId');
    final command = field('command');
    final dispatchId = field('dispatchId');
    var ok = false;
    try {
      final handler = _handlers[ownerId];
      // Stale context guard: only the context this client last published for
      // the owner may execute; a command for a replaced/cleared one is dropped.
      if (handler != null && command.isNotEmpty && _contexts[ownerId] == contextId) {
        await handler(command);
        ok = true;
      }
    } finally {
      // The host router holds one command in flight until it is completed.
      if (dispatchId.isNotEmpty) {
        unawaited(_invoke('complete', jsonEncode(<String, Object>{
          'dispatchId': dispatchId,
          'ok': ok,
        })));
      }
    }
  }

  /// Single path to the host. A host without the channel (tests, standalone
  /// Flutter) or a rejected call is not fatal: the dock simply keeps its state.
  Future<void> _invoke(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // No host dock attached.
    } on PlatformException catch (error) {
      debugPrint('INGE_DOCK_CHANNEL_ERROR method=$method code=${error.code}');
    }
  }

  // ---- Backdrop provider -------------------------------------------------
  // The host dock cannot sample the Flutter surface, so Flutter hands it the
  // strip behind the dock: a small PNG of the bottom band of the root
  // boundary plus its luminance, scoped to the owner that captured it.

  static const double _stripLogicalHeight = 160;
  static const int _stripMaxWidth = 144;

  final GlobalKey backdropBoundaryKey = GlobalKey(debugLabel: 'dockBackdrop');
  String _backdropOwner = '';
  int _backdropSequence = 0;
  bool _backdropBusy = false;
  final List<Timer> _backdropTimers = <Timer>[];

  /// Schedules captures for the current owner; a newer request replaces any
  /// pending one. Callers use it only on discrete content changes.
  void requestBackdrop([List<int> delaysMs = const <int>[250]]) {
    if (_backdropOwner.isEmpty) return;
    for (final timer in _backdropTimers) {
      timer.cancel();
    }
    _backdropTimers.clear();
    final owner = _backdropOwner;
    final sequence = ++_backdropSequence;
    for (final delay in delaysMs) {
      _backdropTimers.add(Timer(Duration(milliseconds: delay), () {
        unawaited(_captureBackdrop(owner, sequence));
      }));
    }
  }

  void _cancelBackdrop() {
    for (final timer in _backdropTimers) {
      timer.cancel();
    }
    _backdropTimers.clear();
    ++_backdropSequence;
  }

  bool _backdropStale(String owner, int sequence) =>
      sequence != _backdropSequence || owner != _backdropOwner || !_payloads.containsKey(owner);

  Future<void> _captureBackdrop(String owner, int sequence) async {
    if (_backdropBusy || _backdropStale(owner, sequence)) return;
    final context = backdropBoundaryKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (context == null || renderObject is! RenderRepaintBoundary
        || !renderObject.attached || !renderObject.hasSize) return;
    final size = renderObject.size;
    if (size.width < 1 || size.height < 1) return;
    // Transparent Flutter pixels show the host page colour, never black.
    final pageColor = Theme.of(context).scaffoldBackgroundColor.withAlpha(255);
    // The host dock sits above the system navigation inset: if this view
    // extends under it, the strip ends where the inset starts.
    final view = View.of(context);
    final bottomInset = view.viewPadding.bottom / view.devicePixelRatio;
    _backdropBusy = true;
    ui.Image? full;
    ui.Image? strip;
    try {
      final ratio = math.min(0.4, _stripMaxWidth / size.width);
      full = await renderObject.toImage(pixelRatio: ratio);
      final bottom = math.max(1.0, (size.height - bottomInset) * ratio);
      final top = math.max(0.0, bottom - _stripLogicalHeight * ratio);
      final width = full.width;
      final height = math.max(1, (math.min(bottom, full.height.toDouble()) - top).round());
      final src = Rect.fromLTWH(0, top, width.toDouble(), height.toDouble());
      final dst = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
        ..drawRect(dst, ui.Paint()..color = pageColor)
        ..drawImageRect(full, src, dst, ui.Paint()..filterQuality = ui.FilterQuality.low);
      final picture = recorder.endRecording();
      strip = await picture.toImage(width, height);
      picture.dispose();
      final straight = await full.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
      final raw = await strip.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await strip.toByteData(format: ui.ImageByteFormat.png);
      if (straight == null || raw == null || png == null || _backdropStale(owner, sequence)) return;
      // Coverage of the captured rows (diagnostic only).
      final source = straight.buffer.asUint8List();
      var opaque = 0;
      var total = 0;
      final rowStart = top.floor();
      final rowEnd = math.min(full.height, rowStart + height);
      for (var y = rowStart; y < rowEnd; y += 2) {
        for (var x = 0; x < width; x += 2) {
          if (source[(y * width + x) * 4 + 3] > 8) opaque++;
          total++;
        }
      }
      // Robust luminance of the composited strip: 10 % trimmed mean.
      final bytes = raw.buffer.asUint8List();
      final samples = <double>[];
      for (var i = 0; i + 3 < bytes.length; i += 16) {
        samples.add((0.2126 * bytes[i] + 0.7152 * bytes[i + 1] + 0.0722 * bytes[i + 2]) / 255);
      }
      samples.sort();
      final trim = samples.length ~/ 10;
      final kept = samples.sublist(trim, samples.length - trim);
      final luma = kept.isEmpty ? -1.0 : kept.reduce((a, b) => a + b) / kept.length;
      final image = 'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}';
      final payload = jsonEncode(<String, Object>{'owner': owner, 'image': image, 'luma': luma});
      if (payload.length > 65536) return;
      final tone = luma < 0 ? 'unknown' : (luma < 0.38 ? 'dark' : (luma < 0.62 ? 'mid' : 'light'));
      debugPrint('INGE_DOCK_BACKDROP_METRICS owner=$owner imageSize=${full.width}x${full.height} '
          'cropRect=0,${top.round()},$width,$height '
          'opaqueRatio=${total > 0 ? (opaque / total).toStringAsFixed(2) : '0'} '
          'luma=${luma.toStringAsFixed(3)} tone=$tone');
      await _invoke('backdrop', payload);
    } catch (_) {
      // Capture is best effort; the dock keeps its last valid frame.
    } finally {
      full?.dispose();
      strip?.dispose();
      _backdropBusy = false;
    }
  }
}

/// Root boundary of a Flutter surface hosted under the host dock. Home and
/// Renditions share it; it also refreshes the dock backdrop once a scroll
/// settles, never while it moves.
class DockBackdropBoundary extends StatelessWidget {
  const DockBackdropBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        DockContextClient.instance.requestBackdrop();
        return false;
      },
      child: RepaintBoundary(
        key: DockContextClient.instance.backdropBoundaryKey,
        child: child,
      ),
    );
  }
}
