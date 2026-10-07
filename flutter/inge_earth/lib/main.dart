import 'dart:async';

import 'package:flutter/material.dart';

import 'biometric_gate.dart';
import 'beta_diagnostics.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BetaDiagnostics.initialize();
  runApp(const SizedBox.shrink());
}

@pragma('vm:entry-point')
void homeMain() {
  WidgetsFlutterBinding.ensureInitialized();
  BetaDiagnostics.initialize();
  unawaited(
    BetaDiagnostics.record(
      category: 'STARTUP',
      severity: 'INFO',
      code: 'FLUTTER_ROOT_STARTED',
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      BetaDiagnostics.record(
        category: 'PERFORMANCE',
        severity: 'INFO',
        code: 'FLUTTER_FIRST_FRAME',
      ),
    );
  });
  runInGeHome();
}

@pragma('vm:entry-point')
void biometricMain() => runBiometricGate();
