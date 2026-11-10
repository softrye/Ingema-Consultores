# HANDOFF TÉCNICO PARA CLAUDE — InGe+ Android

**Fecha del corte:** 04/11/2026 (Lima, Perú).  
**Repositorio:** C:\Users\PC-02\Documents\InGePlus\AppCalicatasDemo  
**Último HEAD comprobado:** b62d1b5 (docs(auth): verify Google provider and Android redirect activation).  
**Autoría de esta bitácora:** ChatGPT, con base en los cambios realizados en esta conversación, código actual y cuatro informes de ingeniería existentes.

> **CRÍTICO:** El repositorio está compartido por varios ingenieros. Su git status contiene decenas de archivos modificados que no pertenecen íntegramente a estas tareas. NO atribuir todo el diff a ChatGPT. NO aplicar reset, checkout global, borrado de untracked ni commit masivo. No usar service_role. Leer AGENTS.md. Por petición del usuario ChatGPT NO ha compilado ni instalado APK.

## 1. Estado resumido a la fecha

| Área | Intervención de ChatGPT | Estado real |
|---|---|---|
| Botón Google | Marca real, centrada, sin texto visible, acción accesible conservada | Código UI presente; OAuth no certificado |
| Google OAuth callback | Diagnóstico PKCE y deep link; timeout/etiqueta de fallo corregidos | Causa externa pendiente |
| Presencia Rendiciones | Canal Realtime compartido, sectores/focos/avatares integrados | Pruebas estáticas; web ZIP sólo tiene protocolo v1 |
| Picker ubicación | Inspección de motor topo | Corrección encontrada en worktree de OTRO ingeniero |
| Calicatas media HTTP400 | Registro sanitizado del error RPC para diagnóstico | Causa raíz HTTP400 pendiente |
| LIVE remoteRevision=0 | Auditoría de salvaguardas de versiones | Protección existente; no nuevo fix |
| Rendiciones HTTP500 | Diagnóstico de HTTP real vs enum Qt NetworkError=401 | HTTP500 sigue pendiente |
| PDF Calicatas | Renderer A3 por páginas, correction safeFileName | El usuario confirmó que exporta igual; no modificar |
| XLSX inicial | Plantilla QRC y exportador paginado | Fase histórica SUPERADA |
| XLSX final | Libro QXlsx generado en blanco, formato reconstruido según web | Código y tests estáticos; pendiente nuevo build/QA |
| Dock contextual | Responsive en tablet/plegable abierto, versión compacta | Código y tests; validar alineación final |

## 2. Detalle cronológico

### 2.1. Login: icono oficial de Google
Solicitud: quitar el texto visible Continuar con Google, dejando solamente el logotipo multicolor original sin el artefacto visual detectado por el usuario.
- qml/Mobile/Main.qml, componente googleButton: Image centrada con source qrc:/images/google_mark.png, tamaño 34*u, PreserveAspectFit, smooth y mipmap.
- Se conserva ancho/radio del control, MouseArea y signInWithGoogle(), además de Accessible.name Continuar con Google para accesibilidad. El texto no se pinta.
- Recurso images/google_mark.png y QRC de marca. Comprobar el diff y atribución, porque Main.qml y los recursos son compartidos.
- Este cambio es sólo UI, NO corrige por sí solo OAuth ni la configuración externa.

### 2.2. Rendiciones: Realtime/presencia/foco v2 de Android
Se consultó el ZIP web ingeplus-main (1).zip, archivo src/components/renditions/RenditionLivePresence.tsx.
- El código web real usa canal privado rendition:<renditionId>, track con userId, name y routeIds, y broadcast invalidate.
- El ZIP NO implementa field, avatarUrl ni color en la presencia de Rendiciones; por tanto NO se puede certificar paridad web↔Android v2.
- src/cpp/supabaserealtimechannel.h/.cpp: soporte del periodo de estabilización fieldSettleMs (general 180 ms, Rendiciones 150 ms), control de foco/limpieza cuando se abandona sesión/ventana.
- qml/Mobile/renditions/RenditionsApp.qml: canal vinculado al ID remoto al abrir y editar, recepción, invalidación y salida de segundo plano.
- qml/Mobile/renditions/RCard.qml: propaga foco de control al campo/sector de presencia.
- qml/Mobile/renditions/RenditionDetail.qml: sector Datos de la rendición.
- qml/Mobile/renditions/RenditionFinancial.qml: sectores Financiamiento y Tipo de cambio.
- qml/Mobile/renditions/RenditionDocuments.qml: presencia en documentos de gastos.
- qml/Mobile/renditions/RenditionReceived.qml: participantes visibles sin publicar foco falso por mera lectura.
- Existentes y reutilizados: qml/Mobile/components/PresenceAvatars.qml y FieldPresenceHighlight.qml, src/cpp/presenceidentity.h/.cpp. No considerar que ChatGPT creó íntegramente esos componentes.
- tests/renditions/presence_v2_android_static.cjs: prueba estática PASS. No hubo dos dispositivos y dos cuentas en runtime.
- Pendiente: contrato v2 interoperable con la web, acceso real a Realtime/Storage, permanencia de canales y sincronización tras reconexión.

### 2.3. Diagnóstico de cinco problemas del emulador
Se inspeccionaron logcat y videos de 15,424 y 31,317 s.
1. OAuth Google: android/AndroidManifest.xml, InGeOAuthCallbackActivity.java, InGeQtActivity.java, authsession.cpp. Se verificó esquema com.ingema.ingeplus://login-callback, singleTop y PKCE S256 existentes. En authsession.cpp la espera al volver de navegador subió de 2.500 a 5.000 ms; la ausencia de callback ahora informa OAUTH_CALLBACK_MISSING, en vez de falsa OAUTH_CANCELLED. La raíz Cloud/Supabase/deeplink requiere diagnóstico externo y prueba final.
2. Ubicación: logs históricos engine=none y Unable to assign [undefined] to bool. La versión concurrente de CalicataPointPicker.qml ya usa CalicatasTopoMap con engine=topo y mapSupported booleano; NO atribuir esa reparación a ChatGPT.
3. Calicatas: cuatro CAL-MEDIA-READ HTTP_400 (uno de logos y tres de fotos) tras hidratar segunda calicata. calicatacloudservice.cpp añadió registro INGE_CAL_MEDIA_READ_STATE_RPC_FAILED con httpStatus, qtNetworkError y backendCode para get_my_calicata_media_read_state_v01; no se imprimen secretos o IDs. La migración se revisó en backend remoto, sin aplicar SQL. El HTTP400 NO se arregló.
4. LIVE remoteRevision=0/localRevision=3: revisadas defensas existentes en calicatacloudservice.cpp y CalicatasEditorPage.qml para no sobrescribir edición local. No se creó un segundo sistema de versiones; pendiente validar reconexión.
5. Rendiciones: http=500 networkError=401 NO es HTTP 401. Se trata de HTTP500 y enum QNetworkReply::InternalServerError=401. Refresh JWT para HTTP401 genuino ya estaba en RenditionRepository/AuthSession; el HTTP500 backend sigue abierto.
Pruebas: node --test tests/calicatas/media_purge_read.cjs tests/calicatas/first_open_presence.cjs: 11/11 PASS. Ninguno de esos resultados sustituye pruebas Android.

### 2.4. Corte eléctrico y recuperación del exportador
- El archivo androidcalicataexporter.cpp quedó lleno de 160603 bytes NUL. Fue respaldado como %LOCALAPPDATA%\Temp\ingeplus_exporter_corrupt_20261104_zeros.bin.
- Recuperación focalizada desde código fuente válido 29/10/2026: C:\Users\PC-02\Documents\InGePlus\_work\Ingema_Consultores_Release_20261030\androidcalicataexporter.cpp. NO se restauró la rama completa.
- La versión exacta inmediatamente anterior al corte NO pudo recuperarse; posibles diferencias con modificaciones locales de octubre/noviembre. Revisar antes de retocar funciones antiguas.
- Más respaldos de fuentes previas en %LOCALAPPDATA%\Temp; ver anexos.

### 2.5. Exportación inicial de Calicatas a Excel y PDF
- Error original: No se encontró la plantilla embebida :/templates/Calicata_Formato.xlsx. Se registraron recursos Templates/Calicata_Formato.xlsx y Templates/Calicata_Formato_Paginado.xlsx en resources_mobile_calicatas.qrc para Android.
- Se extrajeron y estudiaron fuentes del ZIP web: exportModel.ts, exportPagination.ts, exportLayout.ts, exportExcel.ts, exportPdf.ts y useCalicataExport.ts.
- Se añadió calicataexportpagination.h: 60 filas x 0,05m = una hoja cada 3,00m, cálculo en centímetros, cortes fragmentados al cruzar límites. Límite inicial máximo 10 hojas/30m; un exceso produce error explícito en lugar de recortar.
- Se añadió calicatawebpagedpdf.inc: PDF Qt vectorial QPdfWriter, A3 horizontal, cabecera, logos, perfil, ensayos, fotografías, N.F., observaciones y varias páginas. El usuario confirmó su funcionamiento/equivalencia. NO modificar esta ruta sin pedirlo.
- Se añadió un primer calicatawebpagedexcel.inc que rellenaba hoja preformateada; esta implementación YA NO ES LA VIGENTE (véase 2.8).
- androidcalicataexporter.cpp enlaza paginación con ambos formatos; mantiene exportaciones y rutas duraderas.
- tests/calicatas/web_export_parity_static.py verifica profundidad: 1,50m→1, 3,00m→1, 7,40m→3; un estrato 2,50–3,50m se reparte entre hojas.
- La documentación CALICATAS_EXPORT_WEB_ANDROID_PARITY_20261104.md refleja esta fase antigua del XLSX y se incluye únicamente como historial.

### 2.6. Error C++ safeFileName encontrado en compilación del usuario
Compilación Android x86_64 Debug realizada por el usuario:
calicatawebpagedpdf.inc:301: use of undeclared identifier safeFileName.
- Causa: safeFileName pertenece a AndroidCalicataExporter y se invocaba desde una función libre.
- Fix: AndroidCalicataExporter::exportCalicataToPdf calcula safeCode y se lo pasa como argumento a renderWebCalicataPdf; función libre ya no accede al método privado.
- Se actualizó web_export_parity_static.py para detectar regresión.
- Después de ese fix, el usuario confirmó que el exportador funcionaba. Posteriormente confirmó el PDF correcto y reportó una discrepancia SOLAMENTE en el Excel.

### 2.7. Dock contextual en tablets y plegables
- Archivo qml/Mobile/HomeScreen.qml, import QtQuick.Window.
- expandedContextDock activa sólo si Qt.platform.os == android, dockMode == subapp, Screen.width/height positivos y lado menor de pantalla >=600 dp.
- Es detección por dimensión, NO lectura nativa de la bisagra. Un plegable abierto entra cuando su lado menor alcanza el umbral; plegable cerrado y celular convencional conservan geometría previa.
- Cuerpo contextual más botón + forman grupo centrado, limitado por márgenes. Posiciones relativas y acciones originales preservadas.
- Primera revisión demasiado grande: ancho máximo 480*u, botón 68*u, iconos 36*u, altura 64*u. El usuario pidió compactar.
- Valor final VIGENTE: ancho máximo 420*u, gap 12*u, botón + 62*u, iconos 32*u, altura 58*u.
- tests/dock/contextual_large_screen_static.cjs pasó casos tablet, plegable abierto/cerrado, teléfono, Home y multiventana. qmllint no encontró error de sintaxis.
- Pendiente comparar visualmente capturas reales y medir márgenes; no asumir pixel-perfect.

### 2.8. Reescritura FINAL del Excel: paridad estructural con la Web
**Esta sección sustituye 2.5 en lo referente al XLSX.**
El usuario entregó QA IA laptop 2026-10-15.xlsx. El archivo Android contenía 1 hoja y 88 merges. La referencia golden del ZIP web calicata-1_5m.xlsx contiene 195 merges en SU propio escenario, no necesariamente misma cantidad de estratos. El motivo real del desacople fue que la web usa ExcelJS generando workbook limpio, mientras Android reutilizaba plantilla antigua con datos/estilos residuales.

Archivos:
- androidcalicataexporter.cpp: exportStateToXlsx usa ahora QXlsx::Document xlsx; y xlsx.addSheet("Calicata N"), sin abrir/copiar Calicata_Formato_Paginado.xlsx. Conserva la selección de proveedor, validación, archivos de salida, verificación de escritura, hash y cola de Google Drive/InGeDrive.
- calicatawebpagedexcel.inc REESCRITO: 55 columnas A:BC con anchos exactos del golden; 89 filas y perfil de 60 x 21,75 pt; título AG1:BC3; proyecto AG4:BC6; coordenadas y metadatos, bandas de humedad/excavabilidad/consistencia, encabezados superpuestos correctos de granulometría y plasticidad, SUCS/AASHTO, estratos, N.F., porcentajes, muestras, fotos y logos, observaciones y leyendas de muestras. Ya no conserva merges/fondos de una plantilla incompatible.
- thirdparty/QXlsx/header/xlsxworksheet.h y source/xlsxworksheet.cpp: nuevo setCalicataA3PrintLayout(), papel A3 landscape, márgenes del Web y fit 1x1; sentinel exclusivo inge-cal-a3 para emitir atributos y evitar relación r:id huérfana. Verificar compatibilidad en runtime.
- tests/calicatas/web_excel_fidelity_static.py compara anchos 55/55 y rangos principales contra golden web dentro del ZIP; web_export_parity_static.py y native_excel_static.cjs actualizados/verificados.
- docs/CALICATAS_EXCEL_FIDELIDAD_WEB_20261104.md registra el reemplazo.

**Estado real:** tests estáticos PASS y diff --check PASS. No hay todavía compilación, instalación, generación ni apertura real del Excel DESPUÉS de esta última reescritura. No declarar fidelidad visual certificada. El PDF no sufrió cambios por este ajuste.

## 3. Validaciones conocidas

- PASS: python tests/calicatas/web_excel_fidelity_static.py (anchos y bloques comparados con ZIP golden).
- PASS: python tests/calicatas/web_export_parity_static.py (paginación, QRC y código).
- PASS: node tests/calicatas/native_excel_static.cjs.
- PASS: node tests/dock/contextual_large_screen_static.cjs (fixtures y geometría).
- PASS: node tests/renditions/presence_v2_android_static.cjs.
- PASS: node --test tests/calicatas/media_purge_read.cjs tests/calicatas/first_open_presence.cjs (11/11).
- PASS: qmllint HomeScreen.qml en revisión del Dock; git diff --check en archivos afectados.
- NO REALIZADO por ChatGPT: build Android, instalación, exportación XLSX posterior a 2.8, comparación render final, pruebas logcat end-to-end, uso multicuenta y recuperación Google OAuth.
- Realizado por usuario: compilación intermedia y hallazgo safeFileName; reporte posterior de PDF correcto y Excel diferente.

## 4. Archivos de interés con atribución delimitada

**Intervenidos en este flujo:** qml/Mobile/Main.qml (bloque visual Google; también trabajado por otros), qml/Mobile/HomeScreen.qml (bloque dock responsive; también compartido), authsession.cpp (timeout/código OAuth), calicatacloudservice.cpp (traza RPC), src/cpp/supabaserealtimechannel.h/.cpp (debounce), qml/Mobile/renditions/RenditionsApp.qml, RCard.qml, RenditionDetail.qml, RenditionFinancial.qml, RenditionDocuments.qml, RenditionReceived.qml (fragmentos de presencia, dentro de archivos compartidos), androidcalicataexporter.cpp, resources_mobile_calicatas.qrc, calicataexportpagination.h, calicatawebpagedexcel.inc, calicatawebpagedpdf.inc, thirdparty/QXlsx/header/xlsxworksheet.h y source/xlsxworksheet.cpp.

**Pruebas/documentos creados o ampliados:** tests/renditions/presence_v2_android_static.cjs; tests/dock/contextual_large_screen_static.cjs; tests/calicatas/web_export_parity_static.py; tests/calicatas/web_excel_fidelity_static.py; tests/calicatas/review_export_static.cjs; docs/RENDICIONES_PRESENCE_WEB_ANDROID_V2_20261104.md; docs/DIAGNOSTICO_EMULADOR_20261104_OAUTH_MEDIA_MAP_RENDITIONS.md; docs/CALICATAS_EXPORT_WEB_ANDROID_PARITY_20261104.md; docs/CALICATAS_EXCEL_FIDELIDAD_WEB_20261104.md.

**Revisados pero no corregidos por ChatGPT:** CalicataPointPicker.qml (TopoMap de otro ingeniero), LIVE revision guards, mecanismo JWT refresh de Rendiciones, infraestructura base presenceidentity y componentes de avatares. La totalidad del diff de Main/Home/Rendiciones/Auth no pertenece a este trabajo.

## 5. Referencias y respaldos

- Referencia web ZIP: C:\Users\PC-02\Downloads\ingeplus-main (1).zip
- Fuente web: ingeplus-main/src/lib/calicatas/exportExcel.ts, exportLayout.ts, exportModel.ts, exportPagination.ts, exportPdf.ts.
- Golden web: ingeplus-main/outputs/calicata-export-fidelity-20260923/calicata-1_5m.xlsx, calicata-3_0m.xlsx, calicata-7_4m.xlsx y PDFs equivalentes.
- Exportación Android previa adjunta al chat: QA IA laptop 2026-10-15.xlsx (no asumir que exista en carpeta de repo).
- Referencias temporales: %LOCALAPPDATA%\Temp\ingeplus_web_export_reference_20261104, ingeplus_exporter_corrupt_20261104_zeros.bin, ingeplus_exporter_restore_before_web_pagination.cpp, ingeplus_android_previous_pdf_renderer_20261104.txt, ingeplus_exporter_before_excel_fresh_20261104.cpp, calicatawebpagedexcel_before_fidelity_20261104.inc.
- Los respaldos TEMP no sustituyen la fuente de verdad del repo.

## 6. Riesgos y pendientes prioritarios

1. **Excel actual:** cuando el usuario lo autorice, compilar y generar un XLSX Android real. Comparar contra la misma ficha en la web, incluyendo fuentes, combinaciones, porcentajes, tramas SUCS, fotos, leyendas, dimensiones y vista de impresión A3. El writer actual aún no tiene QA runtime.
2. **QXlsx thirdparty:** revisar que setCalicataA3PrintLayout() serialice papel/márgenes/fit al guardar y que no impacte otros libros; posible riesgo de contenido sobre celda combinada y borde generado.
3. **NO tocar PDF** que el usuario ya dio por correcto, salvo evidencia nueva y petición expresa.
4. **OAuth:** resolver causa de callback ausente con logcat y dashboards sin loguear credenciales.
5. **Media HTTP400:** inspeccionar backendCode real de RPC; no silenciar incidentes ni purgar/reescribir medios.
6. **Presencia Rendiciones:** prueba con dos sesiones y contrato web v2 genuino; no afirmar compatibilidad de focos con web ZIP v1.
7. **HTTP500 Rendiciones:** identificar backend real, no confundir con número de error Qt 401.
8. **Dock:** verificar captura tablet/plegable abierto, respetar geometría teléfono.
9. **Git compartido:** revisar diff por archivo, no hacer commit masivo ni reset general. Existe un HEAD reciente de otro agente; no asumir que lo hizo ChatGPT.
10. **Recuperación histórica:** restauración exportador desde 29/10 puede tener divergencias con trabajo no respaldado del corte.

## 7. Instrucción de continuidad para Claude

> Lee AGENTS.md y este archivo antes de editar. El proyecto es compartido, así que revisa git status y git diff de los archivos específicos, no restaures cambios ajenos. La prioridad activa es el Excel nativo de Calicatas: verificar su nueva generación desde libro vacío frente a los XLSX golden del ZIP Web. Mantén sin cambios el PDF, que ya está aprobado por el usuario. No compiles si el usuario no lo autoriza; nunca uses service_role. Reporta cada cambio con prueba y separa confirmación estática de QA Android.

## 8. Anexos técnicos

Para conocer los diagnósticos y pruebas completos, lee las cuatro fuentes que siguen. El anexo antiguo de exportación describe un XLSX con plantilla YA SUSTITUIDO por la sección 2.8. No recuperes esa implementación.

---

### Anexo A. Presencia Rendiciones (detalle)

# Rendiciones Android — presencia y foco Realtime (04-11-2026)

## Alcance y estado
- Integración sobre las clases y controles **ya existentes**, sin crear otro cliente Supabase.
- Código editado en Android; **sin compilar, instalar ni probar en dispositivo**, por solicitud explícita.
- Worktree inicial con numerosas modificaciones ajenas: se editaron sólo fragmentos puntuales; no se hizo commit.
- No se tocaron `qml/Mobile/pages/*`, el Dock, el esquema ni las credenciales.

## Web revisada: límite de paridad
Referencia indicada: `C:\Users\PC-02\Downloads\ingeplus-main (1).zip`.
Extraídos a carpeta temporal sólo archivos de búsqueda de presencia/realtime; fuente principal:
`ingeplus-main/src/components/renditions/RenditionLivePresence.tsx`.
El código entregado usa:
- Canal privado: `rendition:<renditionId>`.
- `channel.track({ userId, name, routeIds: [renditionId] })`.
- `broadcast` evento `invalidate` (sin datos de usuario en el aviso).
- Render de avatar **con iniciales**, no foto; **no** envía `field`, `avatarUrl` ni `color`.
**El ZIP no contiene el contrato v2 de foco/fotografía solicitado para Rendiciones.**
No se han inventado nombres de eventos, identificadores de campo ni un protocolo web inexistente en esa versión.

## Android: implementación y reaprovechamiento
- `src/cpp/supabaserealtimechannel.{h,cpp}`: canal autentificado existente, reconexión, leave; control configurable `fieldSettleMs` (180 ms por defecto, **150 ms para Rendiciones**), limpieza del campo al ir a segundo plano o cambiar de documento.
- `src/cpp/presenceidentity.{h,cpp}` (existentes, sin modificar): color FNV-1a a partir del ID real del usuario, referencia privada `storage://avatars/<uid>/…`, URL firmada solicitada por cada receptor, descarga a caché privada y fallback a iniciales. Nunca enviar token/URL firmada por el canal.
- `qml/Mobile/renditions/RenditionsApp.qml`: vínculo del canal con detalle, editor de cabecera, editor de gasto y recepción administrativa; foco limpio en segundo plano, hoja de nueva rendición o cierre. Reusa broadcast `invalidate` y lógica de recarga diferida.
- `qml/Mobile/renditions/RCard.qml`: conecta foco del control hijo al identificador visual de presencia.
- `qml/Mobile/renditions/RenditionDetail.qml`: avatares existentes y halo de encabezado mientras alguien edita datos de la rendición.
- `qml/Mobile/renditions/RenditionExpenses.qml` (ya integrado): halo por `Gasto N`.
- `qml/Mobile/renditions/RenditionFinancial.qml`: halo para `Financiamiento` y `Tipo de cambio` cuando se enfoca un control de su tarjeta.
- `qml/Mobile/renditions/RenditionDocuments.qml`: halo en documentos asociados a un gasto que otra persona está editando.
- `qml/Mobile/renditions/RenditionReceived.qml`: se une al mismo canal, lista compañeros y avatares en vista de recepción, sin publicar un foco ficticio al solo leer.
- `qml/Mobile/components/PresenceAvatars.qml` y `FieldPresenceHighlight.qml` preexistentes; no duplicados.
- CMake ya enumera los servicios y los dos QML; **no se agregaron QRC/qmldir ni nuevos tipos**.

## Qué comprobar al compilar el usuario
1. Instalar Android y entrar con **cuenta A**; abrir una rendición ya sincronizada con `remoteId`.
2. Entrar con **cuenta B** en la **web** sobre el mismo `renditionId`. Validar que cada sesión vea a la otra. Con el ZIP web revisado se esperan **iniciales**, no fotos ni halo en esa web.
3. Entrar con **cuenta B en otro Android** con esta implementación. Comprobar la foto de perfil cuando haya `storage://avatars` accesible, o inicial si no.
4. Desde A abrir «Editar rendición», enfocarse en nombre; B debe iluminar «Datos de la rendición». Pasar a otro campo y cerrar editor: limpiar halo.
5. Desde A abrir un gasto, enfocar su formulario; B debe iluminar la tarjeta correspondiente en Gastos y Documentos.
6. Desde A ir a Finanzas y enfocar los campos de importe o tipo de cambio; B debe ver el halo correcto, color y etiqueta.
7. Desde recepción administrativa, comprobar avatares sin edición falsa. Desde una cuenta sin acceso, el canal privado debe rechazar la unión.
8. Cambiar de rendición, mandar Android a segundo plano, matar app y volver: no deben quedar participantes/focos fantasmas; al regresar debe reconectar.
9. Probar modo claro/oscuro, teclado abierto, red interrumpida y reconexión; al recibir `invalidate`, se vuelven a pedir datos autorizados, sin confiar en metadatos de presencia para editar valores.

## Riesgos / pendientes explícitos
- **Paridad v2 web no certificable:** el ZIP no implementa fotos ni foco para Rendiciones. Para cumplir el requisito bidireccional hay que aportar la fuente de esa v2 web o incorporarle el mismo contrato.
- `field` es actualmente una **etiqueta de sector** en Android (`Gasto N`, `Financiamiento`, `Tipo de cambio`, `Datos de la rendición`). No hay IDs de campo/sector compartidos en la web del ZIP; las numeraciones podrían diferir entre sesiones con orden de gastos distinto.
- No se verificaron las políticas de acceso Realtime/Storage ni la firma de avatares contra backend real.
- No se compiló ni inspeccionó logcat; no se afirma aprobación funcional o visual.

## Verificación estática
```powershell
node tests/renditions/presence_v2_android_static.cjs
git diff --check -- src/cpp/supabaserealtimechannel.cpp src/cpp/supabaserealtimechannel.h qml/Mobile/renditions
```
La primera prueba verifica la presencia de conexiones, contratos y recursos en fuentes; **no sustituye** prueba de runtime Qt/Supabase.


---

### Anexo B. Diagn?stico de emulador (detalle)

# Diagnóstico de emulador — 04-11-2026 (sin compilación)

## Evidencia visual / Paso 0
Archivo exacto revisado: `C:\Users\PC-02\AppData\Local\Packages\Microsoft.ScreenSketch_8wekyb3d8bbwe\TempState\Recordings\20261104-1450-02.2540915.mp4` (15,424 s).
Se extrajeron 12 fotogramas mediante ffmpeg; mosaico temporal: `%LOCALAPPDATA%\Temp\inge_original_12_frames.jpg`.
Video adjunto adicional: `20261104-1452-41.6753354.mp4` (31,317 s); otros 12 fotogramas inspeccionados.
Hallazgo: panel «Estado de Calicatas», 4 incidencias bloqueantes. Todas «No se pudo recuperar o sincronizar un medio», código CAL-MEDIA-READ, causa HTTP_400; primera General · Logos y tres de Fotos. No se ven errores distintos en ese recorrido.

## 1. OAuth Google
- `android/AndroidManifest.xml`: InGeQtActivity singleTop; callback separado exported, VIEW BROWSABLE `com.ingema.ingeplus://login-callback`.
- `android/src/com/ingema/ingeplus/InGeOAuthCallbackActivity.java`: recibe esquema/host exactos, entrega URI antes de CLEAR_TOP/SINGLE_TOP y finish(). `InGeQtActivity.java`: onNewIntent y entrega estática presentes.
- `authsession.cpp`: `redirect_to` coincide, code_challenge S256 y POST grant_type=pkce presentes. Al volver sin callback, el temporizador antiguo emitía OAUTH_CANCELLED sin evidencia de `access_denied`.
- Ajuste de `authsession.cpp`: espera hasta 5 s el retorno tardío y registra OAUTH_CALLBACK_MISSING, no falsa cancelación. El error externo DEEPLINK/Google/Supabase permanece PENDIENTE hasta prueba en dispositivo. No se declarará Google Sign-In reparado con este solo ajuste.
- `docs/google_signin_setup.md` exige Client ID/secret web en Supabase, URL HTTPS `https://aalmeaqhhlhzwwzsbbxz.supabase.co/auth/v1/callback` en Google Cloud y redirect custom de Android en Supabase. La configuración externa **no se verificó**.

## 2. Ubicación
- Logcat histórico: `INGE_LOCATION_PICKER_OPEN engine=none` y `CalicataPointPicker.qml:57:5 Unable to assign [undefined] to bool`.
- En worktree **ya modificado por otro ingeniero**: `qml/Mobile/pages/CalicataPointPicker.qml` usa `CalicatasTopoMap`, `layer=topo`, `mapSupported: true` booleano y registra `engine=topo`. No se sobrescribió.
- Validar con build/logcat del usuario; no fue probado en dispositivo.

## 3. Cuatro incidencias Calicatas
- Logcat segunda calicata: HYDRATE_OK, luego aura error, panel con 4 CAL-MEDIA-READ / HTTP_400.
- `calicatacloudservice.cpp` `readCalicataState` usa RPC `get_my_calicata_media_read_state_v01` para preflight de logos y fotos. Un único fallo de lectura puede afectar a varios slots.
- La migración local `supabase/migrations/20261102144156_calicata_purged_media_read_state_v01.sql` figura en **historial remoto** de Supabase; no se aplicó ninguna migración ni se reescribió Storage.
- Los callbacks de `CalicataFormPage.qml` ya comprueban `instanceId`, evitando adopción obvia de la calicata anterior. No hay prueba de que el problema sea arrastre de pestaña.
- Cambio mínimo `calicatacloudservice.cpp`: traza `INGE_CAL_MEDIA_READ_STATE_RPC_FAILED httpStatus=... qtNetworkError=... backendCode=...` exclusivamente si falla ese RPC. No imprime tokens, payload, identificadores ni rutas. **La raíz exacta del HTTP 400 aún no está verificada**: hace falta el código backend del siguiente logcat o respuesta HTTP sanitizada. Se conservan las cuatro incidencias legítimas; no se silencian.

## 4. LIVE revalidate
- Código existente `calicatacloudservice.cpp` impide adoptar una `serverRevision` menor que la versión local confirmada; `CalicatasEditorPage.qml` carga solamente si está SYNCED y sin edición pendiente.
- `remoteRevision=0` del evento no se utiliza como base de escritura, sino señal para leer snapshot remoto y validar versión real. No se modificó: requiere validación en dispositivo con reconexión.

## 5. Rendiciones HTTP
- Logcat muestra `http=500 networkError=401`, que en Qt significa **HTTP 500** y **QNetworkReply::InternalServerError (valor numérico 401)**, NO HTTP 401. No es prueba de JWT expirado.
- Worktree existente: `src/cpp/renditionrepository.cpp` usa `httpStatus` / `qtNetworkError`, refresca token si expira y reintenta una única vez ante HTTP 401 genuino; `authsession.cpp` implementa single-flight refresh.
- `src/cpp/renditionconnectivity.h` clasifica status HTTP 401 como Auth, no servidor caído. Error HTTP 500 del servidor sigue pendiente de diagnosticar (no debe disfrazarse como refresh del JWT).
- No se modificaron Rendiciones ni Dock.

## Verificación
- `node --test tests/calicatas/media_purge_read.cjs tests/calicatas/first_open_presence.cjs`: **11/11 PASS**.
- `git diff --check -- authsession.cpp calicatacloudservice.cpp`: **PASS**, con avisos de normalización LF/CRLF no bloqueantes.
- No compilación, APK, instalación, pruebas logcat postcorrección, certificados Google Cloud ni permisos live de Supabase/Storage.
- Worktree con cambios previos de otros ingenieros; no se hizo commit para no incorporar modificaciones ajenas accidentalmente.

## Para verificar después de compilar
1. OAuth: filtrar `INGE_OAUTH_CALLBACK_RECEIVED|OAUTH_EXCHANGE_STARTED|OAUTH_RESULT`. Si no hay callback, verificar en dashboards redirect URL, proveedores y consent screen. No registrar code/verifier.
2. Ubicación: al abrir selector debe salir `engine=topo`; no binding undefined ni pantalla sin motor.
3. Segunda calicata: inspeccionar nuevas `INGE_CAL_MEDIA_READ_STATE_RPC_FAILED`; confirmar HTTP, error de Qt y backend code. Comparar con las 4 incidencias; conservar archivos y no resubir medios sin confirmación.
4. Reconnect: `remoteRevision=0` no debe sobrescribir campos locales ni disparar conflictos ficticios.
5. Rendiciones: observar `httpStatus` real y `qtNetworkError` por separado; probar 401 real con refresh serializado y distinguir 500 backend. Probar reconexión.


---

### Anexo C. Exportaci?n inicial hist?rica (XLSX sustituido)

# InGe+ Android: exportación Calicatas / contrato web (04-11-2026)

## Estado
Implementación nativa en código, **no compilada ni probada en Android** por instrucción del usuario.
Se mantiene Qt 6.9.3, C++/QML y QXlsx, sin Office/COM, sin service_role y sin cambios al Dock.
La equivalencia visual exacta (comparación PDF/Excel renderizados) **no está certificada** hasta compilar, generar ambos formatos y compararlos con fixtures de la web.

## Referencia web inspeccionada
`C:\Users\PC-02\Downloads\ingeplus-main (1).zip`:
- `src/lib/calicatas/exportModel.ts`: datos de ficha, estratos, laboratorio, muestras, logos y fotos.
- `src/lib/calicatas/exportPagination.ts`: aritmética exacta en centímetros.
- `src/lib/calicatas/exportLayout.ts`: columnas, colores, leyendas y posiciones por hoja.
- `src/lib/calicatas/exportExcel.ts`: libro construido con ExcelJS.
- `src/lib/calicatas/exportPdf.ts`: vector PDF con pdf-lib y **A3 apaisado**.
- `src/components/calicatas/useCalicataExport.ts`: conexión de datos y archivos.
Se extrajeron temporalmente sólo las fuentes necesarias a `%LOCALAPPDATA%\Temp\ingeplus_web_export_reference_20261104`.
El ZIP además incluye archivos golden `outputs/calicata-export-fidelity-20260923/` (1,50 m, 3,00 m y 7,40 m). No se copiaron resultados congelados al APK.

## Causa raíz del fallo de la captura
`androidcalicataexporter.cpp` busca `:/templates/Calicata_Formato.xlsx` pero el binario móvil empaquetaba sólo `resources_mobile_brand.qrc` y `resources_mobile_calicatas.qrc`; `resources.qrc` con las plantillas estaba reservado al target Desktop.
Se registraron **ambas plantillas físicas** en `resources_mobile_calicatas.qrc`, usando el prefijo `/templates`:
- `Templates/Calicata_Formato.xlsx`
- `Templates/Calicata_Formato_Paginado.xlsx` (10 hojas preparadas con el formato original).
Los recursos coincidían con los del ZIP web, por lo que no fue necesario sobrescribir la plantilla original.

## Recuperación tras corte eléctrico
El archivo `androidcalicataexporter.cpp` estaba completamente lleno de bytes NUL, de tamaño 160603.
Se conservó como `%LOCALAPPDATA%\Temp\ingeplus_exporter_corrupt_20261104_zeros.bin`.
Se restauró una **copia fuente válida del 29-10-2026**, ubicada en `C:\Users\PC-02\Documents\InGePlus\_work\Ingema_Consultores_Release_20261030\androidcalicataexporter.cpp`, no desde el índice Git (que era más antiguo).
SHA256 del origen restaurado (prefijo): `c06dc61b389d277f1eab`.
La versión de 04-11 previa al corte no se recuperó exactamente; comparar funcionalidades posteriores es necesario. La copia anterior al port paginado quedó también en `%LOCALAPPDATA%\Temp\ingeplus_exporter_restore_before_web_pagination.cpp`.
El antiguo renderer PDF se conservó en `%LOCALAPPDATA%\Temp\ingeplus_android_previous_pdf_renderer_20261104.txt`.

## Exportación implementada
- `calicataexportpagination.h`: una sola definición de páginas y fragmentos para PDF y XLSX; aritmética entera en centímetros, 60 filas x 0,05 m por página, fragmentación de estratos en límites de 3 m. Si una profundidad supera diez páginas (>30 m), informa error en lugar de cortar.
- `calicatawebpagedexcel.inc`: reutiliza las hojas preformateadas, elimina las sobrantes antes de definir áreas de impresión, conserva alto de filas, escribe campos, perfiles, SUCS, N.F., laboratorio, porcentajes, muestras, fotos, logos y observaciones. Las partes continuadas no repiten valores numéricos del laboratorio.
- `calicatawebpagedpdf.inc`: render vector con QPdfWriter en A3 horizontal, mismo modelo de páginas/cortes, colores y posiciones referidos al formato web, mismas fotos/logos/observaciones. Cada página es una página PDF.
- `androidcalicataexporter.cpp`: incluye los dos renderizadores compartidos y usa la plantilla paginada de QRC. El PDF se regenera atómicamente mediante QSaveFile; no reutiliza un PDF A4 anterior con el mismo hash.
- `resources_mobile_calicatas.qrc`: empaquetado para Android.
- `tests/calicatas/web_export_parity_static.py`: fixtures y estructura OOXML sin ejecutar compilación.
- `tests/calicatas/review_export_static.cjs`: actualización de las comprobaciones obsoletas del renderer PDF que estaban acopladas al código A4 anterior.

## Pruebas estáticas realizadas
```powershell
python tests/calicatas/web_export_parity_static.py
node tests/calicatas/native_excel_static.cjs
git diff --check -- androidcalicataexporter.cpp resources_mobile_calicatas.qrc
```
**PASS**: 10 hojas con formato A3 apaisado, 60 filas de 21,75 pt, recursos QRC, código compartido, fixtures 1,50 m → 1 hoja; 3,00 m → 1 hoja; 7,40 m → 3 hojas; 2,50–3,50 m → fragmentos en filas 72–81 de la hoja 1 y 22–31 de la hoja 2.
La suite `review_export_static.cjs` puede detenerse en una aserción **ajena a exportación** sobre `dockCommandRouter.dispatchGlobal("inge.core")` en `Main.qml`; se dejó el Dock intacto.

## Pruebas obligatorias cuando compile el usuario
1. Exportar una ficha de 1,50 m: 1 hoja en XLSX y 1 página en PDF; abrir ambos y cotejar contenido.
2. Profundidad exacta 3,00 m: 1 hoja sin segunda hoja vacía.
3. Profundidad 7,40 m: 3 hojas/3 páginas; verificar marca 6,00 m y cierre en 7,40 m.
4. Corte de 2,50 a 3,50 m: dividir visualmente en dos páginas, sin duplicar ensayos numéricos.
5. Verificar logo de entidad, logo de proyecto, tres fotos y respaldo de fotos vacías.
6. Comparar el exportado Android con los golden del ZIP web, incluida orientación, tamaño de página, códigos SUCS, campos de laboratorio, cabecera y observaciones. Anotar diferencias visuales.
7. Confirmar generación/sincronización Google Drive/InGeDrive, abrir/compartir y errores significativos si falta algún medio.
8. Revisar logcat, errores QML, QXlsx guardado y QPdfWriter; repetir con dos calicatas abiertas.
9. Confirmar que ninguna calicata local se altera, ni se borran datos, al exportar.

## Limitaciones conocidas
- No hubo compilación C++/QML, instalación de APK, lectura del XLSX generado por Qt ni render del PDF de Android. **No declarar paridad pixel a pixel todavía**.
- La web usa ExcelJS/pdf-lib; Android QXlsx/QPdfWriter. Se porta la distribución y los datos, pero quedan por validar métricas tipográficas, patrones, formatos de porcentaje y ajuste de imágenes en dispositivo.
- La plantilla nativa tiene 10 hojas preparadas (30 m). La web puede construir más; Android informa claramente la limitación.
- La copia recuperada del 29-10 puede carecer de cambios de noviembre que no quedaron guardados en otra copia; revisar contra futuros diffs aportados por otros ingenieros.
- Repositorio ya sucio: sin commit automático ni restablecimiento general de ramas; conservar trabajo ajeno.


---

### Anexo D. Excel estructural actual (detalle)

# Calicatas Android — corrección de fidelidad XLSX a la Web (04-11-2026)

## Solicitud
El Excel Android debe reproducir la ficha Web. El PDF ya fue probado y aceptado por el usuario y **NO debe modificarse**.

## Diagnóstico sobre evidencia real
Se recibió `QA IA laptop 2026-10-15.xlsx` exportado desde Android:
- Una hoja `Calicata 1`; estructura OOXML con **88 rangos combinados**.
- La ficha Web de referencia se encuentra dentro del ZIP `ingeplus-main (1).zip`, `outputs/calicata-export-fidelity-20260923/calicata-1_5m.xlsx`.
- La ficha Web de 1,50 m tiene **195 rangos combinados**. El número cambia con cantidad y longitud de estratos: no debe usarse como igualdad universal, pero sí demuestra la diferencia de estructura del antiguo exportador.
- La Web genera cada hoja desde cero (`src/lib/calicatas/exportExcel.ts`); la versión Android anterior abría `Calicata_Formato_Paginado.xlsx` y escribía encima, dejando celdas, combinaciones y estilos de una maqueta distinta.
- También faltaban encabezados subdivididos de granulometría, plasticidad y estado natural, leyendas, alturas/ancho exactos y la aplicación uniforme del formato de impresión.

## Cambios fuente
1. `androidcalicataexporter.cpp`: `exportStateToXlsx` crea un `QXlsx::Document` nuevo y una hoja por fragmento, en lugar de usar una plantilla previa. Conserva su generación duradera, validación, rutas de salida y cola de Google Drive/InGeDrive. Se elimina la copia de plantilla y su limpieza innecesaria.
2. `calicatawebpagedexcel.inc`: escritor limpio según `exportExcel.ts/exportLayout.ts`, 55 anchos A:BC medidos desde el archivo de referencia, 89 filas con alturas exactas, rangos superiores, subgrupos de laboratorio, profundidad 0,05 m, SUCS, valores, fotos/logos y observaciones. Sin residuos de la plantilla original.
3. `thirdparty/QXlsx/header/xlsxworksheet.h` y `thirdparty/QXlsx/source/xlsxworksheet.cpp`: API específica `setCalicataA3PrintLayout` para dar a hojas QXlsx nuevas A3 apaisado, márgenes exactos, fit 1x1 sin generar r:id huérfano. Condicionada por un sentinel único para no modificar otros documentos.
4. `tests/calicatas/web_excel_fidelity_static.py`: contrasta las 55 anchuras nativas contra el golden Web dentro del ZIP, verifica rangos principales, nuevo flujo, impresión y ausencia de reutilización de plantilla.
5. Se conservan `calicataexportpagination.h` y `calicatawebpagedpdf.inc` sin cambios.

## Validación sin compilar
- `python tests/calicatas/web_excel_fidelity_static.py`: PASS, las 55 anchuras y los principales rangos cotejados.
- `python tests/calicatas/web_export_parity_static.py`: PASS.
- `node tests/calicatas/native_excel_static.cjs`: PASS.
- `git diff --check`: PASS (avisos CRLF por Git sin diferencias de espacios).

## Importante
La implementación se modificó en el repositorio remoto, pero **no se compiló ni se generó un XLSX nuevo**. Por tanto, NO hay confirmación de fidelidad visual ni de funcionamiento final. La versión Android QXlsx todavía necesita compararse con el golden Web después del nuevo build. Los casos recomendados son 1,50 m, 3,00 m, 7,40 m y un estrato 2,50–3,50 m. Comparar Excel en escritorio: cabeceras, logos, tramas SUCS, colores, impresiones A3, muestras, ensayos y fotografías.

`PDF`: se respetó exactamente el renderer existente, sin cambios en `calicatawebpagedpdf.inc`.

No se hizo commit porque el repositorio contiene cambios compartidos de otros ingenieros.

