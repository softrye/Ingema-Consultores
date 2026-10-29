import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:local_auth/local_auth.dart';

const _biometricHost = MethodChannel('inge.biometric/result');

/// Verificación biométrica del sistema (BiometricPrompt vía local_auth) para
/// InGeBiometricActivity. Sin árbol de widgets (Visual Zero, 2026-10-10): la
/// única superficie visible es el diálogo del propio sistema.
void runBiometricGate() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(_authenticate());
}

bool _completed = false;

Future<void> _finish(bool authenticated, String status) async {
  if (_completed) return;
  _completed = true;
  try {
    await _biometricHost.invokeMethod<void>('complete', <String, Object>{
      'authenticated': authenticated,
      'status': status,
    });
  } on PlatformException {
    SystemNavigator.pop();
  }
}

Future<void> _authenticate() async {
  final auth = LocalAuthentication();
  try {
    final enrolled = await auth.getAvailableBiometrics();
    if (enrolled.isEmpty) {
      await _finish(false, 'not_enrolled');
      return;
    }
    final authenticated = await auth.authenticate(
      localizedReason: 'Confirma tu identidad para ingresar a InGe+',
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
    await _finish(
      authenticated,
      authenticated ? 'authenticated' : 'cancelled',
    );
  } on LocalAuthException catch (error) {
    await _finish(false, error.code.name);
  } on PlatformException catch (error) {
    await _finish(false, error.code);
  } catch (_) {
    await _finish(false, 'unavailable');
  }
}
