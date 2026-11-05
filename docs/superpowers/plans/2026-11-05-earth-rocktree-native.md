# InGe Earth: integración nativa RockTree

> Ejecución secuencial mediante superpowers:executing-plans. El usuario pide avanzar directamente y reducir preguntas/tokens. No compilar, instalar ni usar ADB.

**Objetivo:** incorporar la descarga/decodificación de la ingeniería inversa adjunta al motor Qt/RHI existente, con niveles de detalle y presupuestos según GraphicsCore.

**Arquitectura:** proveedor HTTPS RockTree, lector Protobuf acotado, decodificación de mallas y CRN/BC1, selección jerárquica de nodos. El motor, navegación, documentos y UI siguen siendo los actuales. Las estrellas y el shader modificados por Claude se conservan. Cesium no se incorpora como segundo motor.

**Restricciones:** Qt 6.9.3, arm64-v8a, un InGeCoreFlow, sin cambios en Auth/Home/Perfil, sin claves ni dependencia de facturación. No sustituir errores de RockTree por otra fuente. NASA/Sentinel continúan como fuentes explícitas.

**Fuente:** ZIP aportado por el usuario, 45 archivos; algoritmos `client/rocktree_decoder.h`, `rocktree_ex.h`, esquema `proto/rocktree.proto` y descompresor CRN. La consulta inicial HTTPS a PlanetoidMetadata devolvió HTTP 200 (13 bytes) el 2026-11-05. Eso no prueba todavía la descarga/renderización completa.

## Fases

- [x] 1. Fuentes y pruebas de contrato/fixtures añadidas: Protobuf, jerarquía, límites, vértices, UV, índices, texturas múltiples y CRN. Pruebas C++ pendientes de compilar por el usuario.
- [ ] 2. Proveedor, caché HTTPS cancelable, scheduler y viewport: recorrido lazy de BulkMetadata, geometría real, créditos y errores visibles; conservar cámara al cambiar fuente.
- [ ] 3. Enlazar perfiles existentes a caché CPU/GPU, concurrencia y detalle; ajustar selección y navegación; preservar estrellas y atmósfera de Claude.
- [ ] 4. Verificación sin compilar, revisión de diferencias y commits sólo de cambios propios. Documentar lo pendiente de validar en Android.

## Verificación

Pruebas JS de la política usada por QML; pruebas host C++ añadidas al proyecto pero no ejecutadas (requieren compilar); sondas HTTPS de lectura de metadatos y nodos reales; diff/check y regresiones JS existentes. No declarar éxito visual ni rendimiento sin build y teléfono.

## Riesgos y decisiones

- Los endpoints y el formato son no documentados; fallos se reportan con código y estado HTTP sin secretos.
- Los paquetes se tratan como entrada no confiable: límites de tamaño, profundidad, índices y memoria antes de reservar/renderizar.
- JPEG y CRN se convierten a RGBA; no exigir S3TC en Mali.
- No trasladar SDL, el bucle de animación ni herramientas Node del exportador al runtime Android. Integrar sus funciones útiles en los componentes actuales.
- La compatibilidad completa y la cobertura de regiones dependen de respuestas reales; no prometer paridad total con Google Earth.
