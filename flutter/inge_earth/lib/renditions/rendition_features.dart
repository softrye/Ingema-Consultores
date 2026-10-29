// Interruptor central de capacidades de Rendiciones (espejo de
// src/cpp/renditionfeatures.h). IA desactivada por defecto: sin análisis IA,
// sin envío de comprobantes a proveedores IA y sin Smart Fill automático.
// Crear, guardar, presentar y sincronizar nunca dependen de la IA.
// Reactivar exige `--dart-define=INGE_RENDITIONS_AI=true` explícito.
import 'renditions_bridge.dart' show RenditionCommandException;

const bool renditionsAiEnabled =
    bool.fromEnvironment('INGE_RENDITIONS_AI', defaultValue: false);

const renditionsAiDisabledCode = 'AI_DISABLED';

/// Lanza AI_DISABLED cuando la IA de Rendiciones está apagada.
void ensureRenditionsAi({bool enabled = renditionsAiEnabled}) {
  if (!enabled) {
    throw const RenditionCommandException(
      renditionsAiDisabledCode,
      'El análisis IA de Rendiciones está desactivado. Completa los campos manualmente.',
    );
  }
}
