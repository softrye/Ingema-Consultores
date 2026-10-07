import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Privacy-safe bridge to the native beta diagnostics spool.
///
/// User content and credentials are never accepted by this API. The native
/// layer applies a second sanitizer before durable storage and upload.
abstract final class BetaDiagnostics {
  static const MethodChannel _channel = MethodChannel('inge.home/host');
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      unawaited(
        recordError(
          code: 'FLUTTER_FRAMEWORK_ERROR',
          exception: details.exception,
          stack: details.stack,
        ),
      );
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousAsyncHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(
        recordError(
          code: 'FLUTTER_ASYNC_ERROR',
          exception: error,
          stack: stack,
        ),
      );
      return previousAsyncHandler?.call(error, stack) ?? false;
    };
  }

  static Future<void> record({
    required String category,
    required String severity,
    required String code,
    Map<String, Object?> metrics = const <String, Object?>{},
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    try {
      await _channel.invokeMethod<void>('recordDiagnostic', <String, Object?>{
        'category': category,
        'severity': severity,
        'code': code,
        'metrics': metrics,
        'context': context,
      });
    } on PlatformException {
      // Diagnostics must never affect rendering, login or navigation.
    } on MissingPluginException {
      // The standalone Flutter runner has no Qt host, which is expected.
    }
  }

  static Future<void> recordError({
    required String code,
    required Object exception,
    StackTrace? stack,
  }) => record(
    category: 'ERROR',
    severity: 'ERROR',
    code: code,
    context: <String, Object?>{
      'exception_type': exception.runtimeType.toString(),
      if (stack != null) 'stack_summary': _stackSummary(stack),
    },
  );

  static String _stackSummary(StackTrace stack) {
    final summary = stack.toString().split('\n').take(12).join(' | ');
    return summary.length <= 4000 ? summary : summary.substring(0, 4000);
  }
}
