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
