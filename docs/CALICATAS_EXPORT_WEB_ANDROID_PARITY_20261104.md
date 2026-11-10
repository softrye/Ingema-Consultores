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
