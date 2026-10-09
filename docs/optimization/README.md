# Optimización de InGe+ Android por tipo de dispositivo

Evidencia de la auditoría del 2026-10-09 y del trabajo hecho a partir de ella. Se conserva para futuras auditorías: cada hallazgo cita archivo, línea y código real de la rama en esa fecha.

| Archivo | Contenido |
|---|---|
| `PLAN_OPTIMIZACION_DISPOSITIVOS_20261009.md` | Plan por fases (A: arreglos rápidos, B: nivel del dispositivo, C: memoria, D: trabajo grande). |
| `ANEXO_42_HALLAZGOS_20261009.md` | Los 42 hallazgos con evidencia, verificación adversarial, cambio recomendado y riesgos. |
| `hallazgos_20261009.json` | Los mismos hallazgos en JSON (área, id, archivos, veredicto, impacto). |
| `ESTADO_HALLAZGOS.md` | Estado de cada hallazgo: hecho (con commit), pendiente o descartado (con motivo). |

## Método

1. Cinco auditores de solo lectura, uno por área: pantallas, GPU, memoria y arranque, build, Android/Java.
2. Un verificador adversarial por área. Abrió cada archivo citado e intentó refutar el hallazgo. Resultado: 12 confirmados, 30 parciales (con la propuesta corregida) y 0 refutados.
3. Cada cambio aplicado se revisa después con un revisor escéptico por commit, antes de darlo por cerrado.

## Límites

Estos documentos no certifican rendimiento en un dispositivo. Según `AGENTS.md`, cada fase necesita build arm64-v8a, instalación, logcat y regresión en un teléfono real.
