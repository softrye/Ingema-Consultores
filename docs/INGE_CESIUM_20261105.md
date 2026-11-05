# InGe Earth — migración a Cesium 1.147

## Resultado en código

El único viewport activo de Earth pasa a Cesium/WebGL en el WebView Android que ya existía. Los controles, el Dock, formularios, GPS y archivos continúan en QML/C++. El viewport RHI anterior deja de instanciarse. Se incluyen localmente los 345 archivos del runtime compilado de distribución de Cesium 1.147 (21.8 MiB); no se utiliza un CDN ni tokens de los proyectos adjuntos.

El WebView queda debajo de la misma superficie Qt. Un item de scene graph escribe un recorte transparente; Qt sigue dibujando los controles encima y conserva los eventos de entrada. La composición restaura el orden normal y los fondos al cerrar Earth. Se usa una única ventana Qt; no se duplica el Dock ni InGeCoreFlow. El visor requiere Android; otros hosts reportan que no está disponible.

## Funciones incorporadas

- Cielo con el algoritmo estático de Claude: semilla 7, misma densidad, tamaños y colores. Se dibuja detrás del canvas transparente de Cesium. La atmósfera es la de Cesium y se ajusta al perfil; los shaders originales de Claude no se borraron.
- Globo WGS84 continuo: base Natural Earth incorporada, capas NASA/EOX explícitas y geometría RockTree como tileset. Los errores de proveedor se notifican; no se cambia de fuente automáticamente.
- Adaptador RockTree a 3D Tiles: jerarquía de metadatos, bounds, error geométrico y contenido b3dm/GLB con todas las partes/texturas. Los vértices se restan de su origen en doble precisión antes de pasarlos a float; el RTC_CENTER conserva el posicionamiento ECEF sin temblor por coordenadas globales grandes.
- Caché y LOD de Cesium acotados por los perfiles existentes; profundidades máximas y conversión de datos acotada. Cancelación por sesión al cerrar o cambiar de página; solicitudes nativas serializadas para limitar picos de memoria.
- Órbita, pan, zoom, giro, selección, marcadores, medición geodésica y capas KML/KMZ enlazados al controlador existente. Los archivos siguen importándose/exportándose por el código nativo, sin trasladar credenciales ni storage al JavaScript.
- Fronteras Natural Earth 110m incorporadas, visibles desde Muy alta, con 331 entidades. Son datos de dominio público; procedencia junto al recurso.
- Captura pequeña de la imagen del mapa, como máximo una vez por segundo en perfiles con vidrio, para alimentar el efecto de vidrio QML existente, tanto en los controles como en el Dock global. No sustituye el viewport ni oculta fallos de renderizado.

## Qué se aprovecha de los tres proyectos

**OpenGlobe:** técnica de coordenadas relativas y precisión del globo; implementada en C++/RTC para Cesium, sin incorporar C#/OpenTK. Fuentes estudiadas: `Chapter05/Jitter/GPURelativeToEye` y sus shaders.

**osgEarth:** jerarquía de terreno, bounds/horizonte y cámara geográfica como requisitos del visor. Las funciones equivalentes quedan a cargo de Cesium y del adaptador de metadatos; no se ha integrado OpenSceneGraph/GDAL ni se afirma haber portado todo osgEarth.

**Locus Earth:** organización de capas, cámara, separación de motor/UI y configuración de recursos. Se implementa el enlace con la UI nativa existente. No se copia su app WebView completa ni se usan sus claves o assets privados de Cesium ion.

Estos proyectos son alternativas y ejemplos, no piezas intercambiables que deban ejecutarse juntas. No se portan sus herramientas de escritorio, ejemplos didácticos ni interfaces duplicadas.

## Verificación y pendientes

Sin CMake, compilación, APK, ADB ni pruebas de teléfono por instrucción del usuario. Se verifica la sintaxis del JS propio con `node --check` y el QML modificado con qmllint de Qt 6.9.3. Los imports/tipos C++ generados no están disponibles al lint desde fuente, por lo que sus avisos no equivalen a una compilación limpia.

La compilación del usuario debe comprobar especialmente el recorte transparente y el orden WebView/Qt, teclado, menús del Dock, regresar a Home, pérdida/recreación del renderer y reapertura de Earth. No se ha demostrado que desaparezca el SIGABRT anterior de Qt/JNI. También requieren validación real la conversión completa b3dm/RTC, carga sostenida y consumo de memoria en A12.

No se declara InGe Earth terminado: faltan verificación visual y de rendimiento, atribuciones específicas de proveedores RockTree y Street View ligado a la configuración de facturación pendiente. No se garantiza paridad completa con Google Earth. Las escenas locales OBJ del viewport anterior no se cargan automáticamente; se informa formato no compatible. Login, AuthSession, Supabase y Calicatas no se modifican.

Comprobaciones realizadas: `node --check` del JS propio (salida 0); qmllint de RetroplasmaEarthView.qml y HomeScreen.qml (salida 0, 447 avisos de análisis desde fuente; no se considera lint limpio); igualdad SHA-256 de los 345 archivos del runtime con el ZIP suministrado; `git diff --cached --check` del código propio sin errores. Se conserva sin modificar el whitespace original de los archivos vendor. Revisión de delimitadores de los cinco archivos Java/C++ nuevos o del puente, en worktree e índice, sin desbalance. Esto no sustituye la compilación.
