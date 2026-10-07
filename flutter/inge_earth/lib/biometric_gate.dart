import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

const _biometricHost = MethodChannel('inge.biometric/result');

void runBiometricGate() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BiometricGateApp());
}

class _BiometricGateApp extends StatefulWidget {
  const _BiometricGateApp();

  @override
  State<_BiometricGateApp> createState() => _BiometricGateAppState();
}

class _BiometricGateAppState extends State<_BiometricGateApp> {
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_authenticate()),
    );
  }

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

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    color: Colors.transparent,
    home: Scaffold(backgroundColor: Colors.transparent),
  );
}
