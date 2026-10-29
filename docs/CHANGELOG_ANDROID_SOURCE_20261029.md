# InGe+ Android — actualización de código fuente del 29/10/2026

**Repositorio:** `softrye/Ingema-Consultores`
**Release:** `android-2026.10.29-source` · **Tipo:** prerelease de fuentes, **sin APK validado**
**Versión anterior:** commit `225470e8b766dd29244989f0dcd788b0234b9e0c` (instantánea del 28/10/2026).

## Resumen de cambios

Esta versión incorpora las correcciones locales del 29/10 en Android. Respecto de la instantánea del 28/10, la comparación de los árboles de código muestra **43 archivos modificados o añadidos; 2.070 líneas añadidas y 252 eliminadas**.

### Rendiciones, Dock y representación visual
- Se ajustó el arranque de la captura de textura de Liquid Glass para que el Dock pueda mostrar su material al abrir la pantalla, sin depender de un productor oculto.
- Se reducen publicaciones de estado idénticas y reconstrucciones innecesarias de delegados; se preservan las filas existentes en listas de rendiciones, gastos, documentos, sustentos, versiones y observaciones.
- Se protegen los shaders frente a texturas nulas y se conserva un material alternativo mientras no esté lista la captura.
- Se agrupan y suspenden recapturas y actualizaciones Realtime durante navegación, ediciones, transición, menús y entrada por teclado; se conservan invalidaciones pendientes.
- Los paneles de edición reutilizan una captura de fondo en lugar de recalcular continuamente el desenfoque durante la interacción.

### Formularios, teclado y revisión
- Se transmite la altura real de la ventana al flujo de interfaz, mejorando el cálculo del área visible.
- El desplazamiento sigue el rectángulo del cursor al editar campos multilínea altos y evita movimientos cuando ya es visible.
- La acción «Siguiente» cambia el foco y las consultas al teclado sin ocultar/reabrir innecesariamente el IME; se mantiene la posición del formulario en transiciones de teclado.
- La devolución directa a **BORRADOR** desde **EN_REVISION** envía el motivo vacío según el contrato RPC inspeccionado. Otras decisiones que necesitan motivo siguen exigiéndolo.
- Se modificaron componentes de exportación de instantáneas, transporte a Google Drive y exportación de Calicatas; estos cambios no implican una validación funcional nueva de los servicios externos.

### Pruebas y documentación
- Nuevos contratos y casos: `tests/renditions/dock_glass_bootstrap.cjs`, `ime_input_contract.cjs`, `qml/tst_render_stability.qml` y `qml/tst_ImeStability.qml`.
- Informes incluidos: `docs/DOCK_GLASS_REVIEW_CORRECCIONES_20261029.md`, `docs/RENDICIONES_RENDER_ESTABILIDAD_20261029.md` y plan de estabilización.
- La documentación local registra ejecuciones QML y Node satisfactorias para escenarios concretos. También registra una suite CTest host con **9/10** y una suite QML preexistente con fallos de fixtures; **no** se declara verde toda la batería.
- **QA pendiente:** construir e instalar en dispositivo Android, comprobar el renderizado real en Samsung A12, teclado Samsung, sincronización autenticada y flujos de exportación. Las pruebas host/offscreen no acreditan el resultado gráfico final.

## Integridad y alcance
- Se preservan los cambios del 28/10, incluidos `qml/Mobile/settings/SettingsApp.qml`, marcas y preferencias.
- Se omitieron videos, capturas, logs y otros archivos bajo `artifacts/`, así como reportes temporales locales.
- No se incluyó un APK, AAB ni binarios firmados. Esta entrega permite auditar y descargar **fuentes**, no instalar una versión probada.
- El tag identifica el commit exacto de esta instantánea; `main` no se fusiona automáticamente.
