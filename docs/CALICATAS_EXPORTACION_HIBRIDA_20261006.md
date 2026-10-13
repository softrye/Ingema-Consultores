# Exportación híbrida Excel — 6 de octubre de 2026

## Cambio solicitado y resultado en fuente

Calicatas conserva un único generador QXlsx y la cola durable RenditionExportService.
El usuario elige Google Drive o InGeDrive (Supabase). El Dock muestra Exportar como
menú, sin comando que suba automáticamente a un destino: Excel → Google Drive y
Excel → InGeDrive. Se quitó el botón ambiguo Exportar Excel del overflow. Entradas
heredadas, como requestExportExcel, abren el selector existente con CalicataLiquidGlass,
CalGlassScrim y WorkspaceMenuButton; no crean otro motor, shader o sistema de animación.
PDF y Ver en InGeDrive siguen en el menú.

exportCurrentExcel captura el proveedor seleccionado durante la generación diferida.
CalicataFormPage lo pasa explícitamente al exportador. GOOGLE_DRIVE usa la autorización
y carpeta Google existentes; SUPABASE usa el bucket privado project-files y las RPC
actuales de InGeDrive. No se intenta otro destino cuando falla el elegido. La publicación
del JSON editable por Supabase conserva su recorrido existente.

El nombre visible de los nuevos Excel Android es exclusivamente código.xlsx:
CT-51+425.xlsx. La causa del sufijo era fileName derivado de la ruta lógica que incluía
el hash. Ahora la cola separa displayFileName de logicalPath/id/sha256. La generación
local usa un directorio privado de operación con UUID y un basename limpio, evitando
sufijos de fecha o hash y sin sobrescribir otros libros locales con el mismo código.
La identidad de la ficha también se conserva internamente en la clave lógica.
La recuperación de una generación después de reiniciar conserva nombre y proveedor.
No se renombran ni eliminan archivos ya publicados anteriormente.

En InGeDrive, un nombre limpio repetido debe crear una versión del mismo documento.
La cola consulta el archivo en el mismo espacio/carpeta, verifica MIME y captura
node_version/binary_content_version. Persiste CREATE/VERSION antes de llamar a la RPC,
para reintentar una respuesta perdida con la misma operación. Las versiones anteriores
se conservan; conflictos o ACL insuficientes siguen siendo errores explícitos.
Google Drive conserva su protocolo de subida previo.

## Archivos

- androidcalicataexporter.h/.cpp: proveedor por solicitud, nombre local y visible,
  reintento solo del documento/destino elegido.
- src/cpp/renditionexportservice.h: displayFileName, recuperación y reserva de versiones.
- qml/Mobile/pages/CalicataFormPage.qml: proveedor e identidad de ficha enviados al generador.
- qml/Mobile/pages/CalicatasEditorPage.qml: selección en Dock/selector Glass y eliminación
  del comando ambiguo.
- tests/calicatas/hybrid-excel-export.cjs: nuevo recorrido híbrido ejecutando JS QML real
  con transporte externo simulado y contratos estáticos de C++.
- tests/calicatas/google-authorization-result.cjs y p6-dock-export.cjs: adaptar las
  expectativas de reintento/doble tap al proveedor explícito.

## Verificación real y límites

Se consultaron las normas actuales de Storage/RLS y el changelog Supabase.
Se confirmó que project-files es privado y que las RPC de carpeta/reserva/finalización
ya existen. No se modificaron políticas, credenciales, tablas ni funciones servidor.
Se ejecutó una prueba real BEGIN/ROLLBACK con identidad de un perfil activo y proyecto
autorizado: carpeta exports, reserva CT-51+425.xlsx en project-files, cancelación de
la reserva de prueba y reserva de versión 2 en el mismo nodo con idéntico file_name.
La transacción terminó en ROLLBACK; no quedó ningún archivo/versión de prueba.
Una primera comprobación esperaba la extensión dentro de document_nodes.name y falló:
el contrato separa nombre/extensión y file_name. Se corrigió la comprobación y la
prueba de reserva/versionado pasó. No se ocultó un cambio del nombre en el servidor.

Pruebas de tests/calicatas y tests/documents: 29 suites pasan. Permanece un fallo
ajeno a este cambio en review_export_static.cjs: exige deshabilitar el asistente
dedicado que ya se habilitó en otra fase. Ese archivo y main_mobile.cpp no fueron
modificados en esta fase. No se declara la batería completa verde.
El nuevo test híbrido pasa: proveedor explícito para ambos destinos, selector para
llamadas antiguas, nombre separado de identidad y recuperación/versionado durables.
Los tests ejecutan JS real; las comprobaciones C++ son estáticas, no un build.

qmllint Qt 6.9.3: exit 0 y cero errores de sintaxis en editor/formulario; success=false
por avisos/metadatos de tipos e imports. No se declara lint sin advertencias.
git diff --check del alcance: sin errores.

Se respetó la instrucción del usuario de no compilar: no se ejecutaron CMake/build,
APK, instalación, ADB ni logcat. Pendiente del usuario: construir e instalar; elegir
ambos destinos con CT-51+425; repetir exportación tras editar; confirmar nombre,
descarga/apertura explícita, versión de InGeDrive, errores sin red y cambio de cuenta.
Un resultado PENDING_SYNC/encolado todavía no confirma la subida. No se afirma
validación completa de Android ni reproducción visual de Glass en dispositivo.

El árbol contiene cambios previos extensos. El commit de esta fase usa únicamente
los hunks propios en fuentes que ya estaban modificadas; p6-dock-export.cjs, antes
sin registrar en Git, se registra como prueba relevante actualizada.
