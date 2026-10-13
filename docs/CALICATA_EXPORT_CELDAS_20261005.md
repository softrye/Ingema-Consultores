# Corrección de exportación Excel — 05/10/2026

El cambio de escala del 03/10 rasterizaba E22:AT81, incluyendo descripciones,
muestras y laboratorio. Los datos nativos se enviaban a BE:BY, fuera de la
ficha. El archivo exportado y los dos videos del usuario confirmaron el error.
Esta corrección sustituye esa implementación; no modifica los espesores.

## Implementación

- `androidcalicataexporter.cpp`: `prepareNativeProfileRows` subdivide las
  filas del cuerpo en los contactos registrados. Cada altura se calcula como
  fracción de la profundidad total multiplicada por la altura original.
  La suma de alturas permanece constante. Se conservan los estilos originales
  y se reasignan fotos, combinaciones, leyenda y área de impresión.
- `writeScaledProfile`: escribe descripción e intervalo real en J:P; tipo e
  intervalo de muestra en AD/AE; resultado, AASHTO y SUCS en AF:AH; laboratorio
  numérico y porcentajes en AI:AP. Humedad, excavabilidad y estabilidad son
  sombreados de celdas. El nivel freático se escribe en Q.
- Las imágenes del perfil se limitan a E:I. No se dibuja texto sobre un bitmap
  y no se crea la tabla auxiliar BE:BY.
- `thirdparty/QXlsx/source/xlsxworkbook.cpp`: actualizar un nombre definido
  existente de igual nombre/ámbito reemplaza su fórmula, evitando dos áreas
  de impresión contradictorias.

La profundidad ingresada permanece independiente del último estrato descrito.
Los intervalos superpuestos o que excedan esa profundidad causan un error.
Una exportación vacía mantiene la escala original de 3 m como plantilla vacía.

## Verificación y límites

Antes del cambio, `native_excel_contract.py` falló sobre el XLSX entregado por
el usuario: una imagen cubría las celdas editables del cuerpo.
Después del cambio se ejecutaron las pruebas JavaScript y las comprobaciones
estáticas. Se ampliaron `checks.cpp` y `golden_contract.py` para comprobar la
exportación real: celdas, porcentajes, una sola hoja, altura impresa, tramo
sin describir, contactos proporcionales y más de sesenta estratos.

**No se ejecutaron CMake, build, instalación, ADB ni logcat.** Fabián compila
y realiza la prueba real. Las pruebas C++ nuevas y el contrato del nuevo XLSX
quedan pendientes de esa compilación y exportación. No se declara validación
Android ni apertura correcta en Microsoft Excel hasta esa prueba.

Un estrato muy fino continúa siendo proporcionalmente pequeño en la ficha:
sus datos están en las celdas y pueden consultarse/editarse aunque el texto
no quepa visualmente. No se agranda su espesor para facilitar la lectura.
La capacidad física de filas de Excel y la memoria disponible siguen siendo
límites del archivo; no hay una división en fichas ni un máximo de 3 m.
Editar texto en el Excel no cambia los datos guardados en la aplicación;
editar el intervalo de muestra no recalcula la geometría exportada.

## Prueba manual

1. Compilar el código actualizado y exportar de nuevo la misma calicata.
2. Seleccionar J, AD, AE, AH y AI:AP: deben ser celdas con datos editables.
3. Mover una trama: solo se desplaza el dibujo E:I; los datos permanecen.
4. Usar profundidad 60 con estratos hasta 30: la regla debe terminar en 60
   y el tramo restante debe quedar sin material inferido.
5. Comparar fotos, pie y tamaño impreso con la plantilla original.
