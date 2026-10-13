import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import 'biometric_gate.dart';
import 'beta_diagnostics.dart';

// Módulo Flutter sin interfaz (Visual Zero, 2026-10-10). Conserva la lógica
// de Rendiciones (lib/renditions), los diagnósticos beta y la verificación
// biométrica del sistema. No se ejecuta ningún runApp.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  BetaDiagnostics.initialize();
}

@pragma('vm:entry-point')
void biometricMain() => runBiometricGate();
