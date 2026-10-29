#pragma once

// Interruptor central de capacidades de Rendiciones en Android.
//
// IA desactivada por defecto (P0 2026-10-14): ninguna ruta de Rendiciones puede
// solicitar análisis IA, enviar comprobantes a un proveedor IA ni aplicar
// Smart Fill automático. Crear, editar, guardar, presentar y sincronizar no
// dependen de la IA. El código reutilizable (contratos, parsers) se conserva.
// Reactivar exige compilar con INGE_RENDITIONS_AI_ENABLED=1 de forma explícita.
#ifndef INGE_RENDITIONS_AI_ENABLED
#  define INGE_RENDITIONS_AI_ENABLED 0
#endif

namespace RenditionFeatures {
inline constexpr bool aiEnabled = INGE_RENDITIONS_AI_ENABLED != 0;
inline constexpr const char *aiDisabledCode = "AI_DISABLED";
inline constexpr const char *aiDisabledMessage =
    "El análisis IA de Rendiciones está desactivado. Completa los campos manualmente.";
} // namespace RenditionFeatures
