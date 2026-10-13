# Verificación focalizada de Calicatas

Este arnés compila los archivos **reales** `calicatadocument.cpp` y
`androidcalicataexporter.cpp`, más el QXlsx del repositorio. `auth_link.cpp`
desconecta únicamente servicios externos en el ejecutable de pruebas.
No simula autenticación dentro de la aplicación Android ni cambia sus fuentes.

La versión final de estos cambios no se ha compilado por instrucción del usuario.
Tampoco se instaló una APK. Los resultados anteriores en `outputs/calicatas-p0`
corresponden a una revisión intermedia, no certifican la revisión final.

Para ejecutar después, desde la raíz del repositorio en PowerShell:

```powershell
$env:PATH = 'C:\Qt\Tools\mingw1310_64\bin;C:\Qt\6.9.3\mingw_64\bin;' + $env:PATH
& 'C:\Qt\Tools\CMake_64\bin\cmake.exe' -S tests/calicatas -B C:/InGeBuild/CalicatasP0Checks -G Ninja -DCMAKE_MAKE_PROGRAM=C:/Qt/Tools/Ninja/ninja.exe -DCMAKE_PREFIX_PATH=C:/Qt/6.9.3/mingw_64 -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe -DCMAKE_BUILD_TYPE=Debug
& 'C:\Qt\Tools\CMake_64\bin\cmake.exe' --build C:/InGeBuild/CalicatasP0Checks --parallel 4
$env:QT_QPA_PLATFORM = 'offscreen'
& 'C:\Users\PC-02\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tests/calicatas/golden_contract.py 'C:\Users\PC-02\Downloads\CT12-85+745.xlsx'
& C:\InGeBuild\CalicatasP0Checks\calicatas_checks.exe outputs/calicatas-p0/golden-fixture.json
$exportFile = Get-Content outputs/calicatas-p0/export-path.txt -Raw
& 'C:\Users\PC-02\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tests/calicatas/golden_contract.py 'C:\Users\PC-02\Downloads\CT12-85+745.xlsx' --output $exportFile
```

El contrato compara estructura, contenido, imágenes y estilos semánticos.
Los índices internos de estilos pueden cambiar al guardar con QXlsx.
Cuando `fitToPage` está desactivado, los atributos de ajuste no afectan la
impresión: se comparan escala, papel, orientación y estado efectivo de ajuste.

El arnés no sustituye pruebas con Gboard, GPS real, cámara/galería, reinicio de
proceso, cambio de cuenta ni apertura del Excel con la aplicación de gerencia.
El perfil usa una sola hoja del tamaño original y una escala de cero hasta la
profundidad ingresada. La corrección del 05/10/2026 elimina la imagen de toda
la tabla y la tabla auxiliar BE:BY. Descripción J:P, muestras AD:AE,
resultados AF:AH y laboratorio AI:AP son celdas editables dentro de la ficha.
Solo las tramas E:I, fotos y logos son imágenes.
Las filas internas se subdividen en los contactos reales: su altura total
permanece constante, y las fotos, leyenda y área de impresión se reasignan.
Editar una descripción en Excel modifica esa celda. Cambiar manualmente un
intervalo de muestra no recalcula automáticamente la geometría del perfil.
El arnés incluye 3, 60 y 1.000 m, un tramo sin describir, cien estratos y rechazo
de intervalos sobre la profundidad. Estas pruebas nativas nuevas quedan
pendientes de compilación y ejecución por Fabián.

Contrato de lectura del archivo generado por la app:

```powershell
& 'C:\Users\PC-02\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tests/calicatas/native_excel_contract.py 'C:\ruta\exportacion-nueva.xlsx'
```

Este contrato detectó la imagen incorrecta del archivo
`calicata_20261003_114958.xlsx` antes de modificar la exportación.
