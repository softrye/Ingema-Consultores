# InGe Earth: pantalla completa, detalle y documentos — 14/10/2026

Estado de esta entrega: **IMPLEMENTADO / SIN COMPILAR Android**. Qt 6.9.3 host: seis suites CTest aprobadas; no se compiló Android, no se usó ADB y no se inició emulador. La prueba visual Android corresponde al usuario.

## Pantalla y navegación

Earth reemplaza únicamente su PageFrame por un Loader de pantalla completa en HomeScreen. RetroplasmaView ocupa todo el Item; búsqueda, acciones y barra inferior flotan sobre el globo. Los márgenes superiores y el espacio del Dock usan los valores existentes de Home; el Dock global no se modifica. El encuadre inicial ajusta el limbo al lado corto de la pantalla, también en orientación vertical.

La píldora abre coordenadas, Perú, Lima y GPS. La columna lateral ofrece norte, GPS, fuentes, zoom y planeta completo. La barra inferior abre lugares, medición, archivos e información. Los datos técnicos quedan en paneles secundarios; coordenadas, altura de cámara, escala y atribución son discretos. La escala intersecta la superficie dibujada y mide la distancia geodésica entre sus extremos. El arrastre responde al zoom; el modo navegación respeta el rumbo. Pinch permite zoom, desplazamiento y giro. Doble toque acerca a la posición seleccionada; pulsación larga crea un marcador.

Back conserva la prioridad del submenú del Dock y cierra primero el panel de Earth o una medición activa; luego vuelve al destino Home/Calicatas original. GPS continúa usando Perms y su único origen compartido, liberando solo el seguimiento iniciado por Earth. No hay botón 2D/3D: este motor es planetario 3D y no incorpora una proyección plana ni edificios 3D.

## Datos y LOD

| Fuente | Datos y cobertura | Límite |
|---|---|---|
| NASA Blue Marble incorporada | Todo el planeta sin red, imagen real 2048×1024 | ~19,6 km/píxel |
| NASA GIBS Blue Marble | Refinamiento mundial, WMS EPSG:4326 | 500 m nativos; nivel 5 ~611 m entregados |
| EOX Sentinel‑2 cloudless 2016 | Mosaico histórico, detalle terrestre donde está disponible; fuente regional predeterminada | 10 m nativos; nivel 11 ~9,55 m solicitados, se informa 10 m efectivos |
| NASA/USGS HLS L30 | Adquisiciones fechadas, cobertura parcial y nubes; selección opcional | 30 m nativos; nivel 9 ~38 m entregados |

Se conserva el globo NASA en todas las vistas. El quadtree pide primero sectores cercanos al objetivo y niveles intermedios, conserva ancestros residentes y sustituye progresivamente la cobertura por tiles más finos. Usa píxeles físicos del viewport para evitar submuestreo en pantallas de alta densidad. Límites existentes: dos trabajadores, 96 solicitudes, CPU 64 MiB, GPU 64 MiB y caché de red 128 MiB. El zoom de cámara admite 2–50.000 km; no crea resolución adicional por debajo de la resolución de la fuente. No hay descarga mundial masiva ni garantía de datos urbanos submétricos.

EOX se conecta únicamente a `https://tiles.maps.eox.at/wms`, capa **s2cloudless**, WMS **1.1.1**, SRS EPSG:4326 y BBOX **oeste,sur,este,norte**. NASA conserva WMS 1.3.0 y su orden **sur,oeste,norte,este**. El GetCapabilities oficial identifica expresamente s2cloudless como mosaico 2016 bajo CC BY 4.0. No se usan las capas posteriores con licencia no comercial. La atribución se muestra en el visor y ampliada en fuentes.

Fuentes verificadas: [EOX Maps](https://maps.eox.at/), [licencia del mosaico 2016 y precios](https://cloudless.eox.at/pricing), [capabilities del servicio](https://tiles.maps.eox.at/wms?SERVICE=WMS&REQUEST=GetCapabilities), [NASA GIBS](https://nasa-gibs.github.io/gibs-api-docs/access-basics/). El servicio gratuito EOX funciona sin SLA y puede limitar tráfico. Ante errores se conserva NASA y se permite reintentar; el panel informa la resolución más fina efectivamente cargada, no la de todas las áreas de la pantalla.

## KML/KMZ y herramientas

Importa Document/Folder/Placemark/MultiGeometry con Point, LineString y Polygon; conserva nombres, coordenadas, anillos, visibilidad del Placemark y colores básicos ABGR. La lista permite centrar en capa o elemento, ocultar/mostrar la capa y quitarla de memoria. Los lugares y la medición pueden guardarse junto con las capas importadas. QML entrega las posiciones al controlador y el mismo renderer QRhi recibe triángulos/texturas de color, sin otro mapa o WebView.

Los polígonos simples locales reciben relleno triangulado y subdividido para seguir el elipsoide. Polígonos con huecos, grandes o excesivamente complejos muestran todos sus contornos y un aviso; sus anillos se conservan al exportar. No se admiten NetworkLinks, overlays raster, modelos 3D, tracks temporales ni iconos externos. KMZ lee un KML (prefiere doc.kml), no extrae archivos y no carga recursos externos; exporta un doc.kml comprimido. No es soporte completo de todos los estilos/jerarquías de KML. La visualización usa colores opacos. Sin DEM, clampToGround se fija al elipsoide y relativeToGround emite un aviso; absolute conserva la altitud.

Límites: archivo 4 MiB; KMZ 256 entradas y suma declarada de 8 MiB; sin symlinks ni rutas de traversal; XML sin DTD/entidades. Máximo global 16 capas, 500 geometrías, 20.000 posiciones y 180.000 vértices estimados. La admisión calcula complejidad antes de generar las mallas; geometrías demasiado extensas se rechazan con explicación. Presupuesto adicional de geometrías 16 MiB, con interrupción del trabajo al agotarse. El archivo original nunca se modifica.

La separación gráfica regional usa 60–71 m; overlays 72 m y picking regional 71 m. Es un sesgo de representación para profundidad, no elevación del terreno ni cambio de las coordenadas almacenadas. Segmentos de línea subdivididos a ≤0,02 grados y rellenos a ≤2,5 km evitan que los interiores queden enterrados por las cuerdas del elipsoide. Una prueba verifica registro del marcador por debajo de un píxel con cámara a 2 km. No sustituye una verificación visual en Android.

Medición: distancia superficial WGS84 mediante Vincenty; cerca de antípodas, fallback explícito de cálculo a arco de gran círculo sobre radio medio. No mide rutas, desnivel ni área. Cambiar de cuenta limpia capas, marcadores y medición de memoria sin borrar documentos. Salir de Earth conserva las capas durante la sesión; la persistencia entre reinicios exige guardar KML/KMZ.

## InGeDrive y Google Drive

EarthDocumentSheet es un adaptador de **NothingDocuments**, no otro cliente de almacenamiento. Dispositivo navega la raíz de documentos de la cuenta; InGeDrive navega espacios y carpetas con el modelo existente. Seleccionar un KML/KMZ remoto llama download(entry), resuelve su versión autorizada y abre el espejo entregado por completed. Guardar crea KML/KMZ local de forma atómica, con otro nombre si ya existe. Abrir una carpeta remota habilita Subir a InGeDrive y usa el flujo existente reserve/begin/upload/finalize.

«Abrir archivo / Google Drive» usa FileDialog y el selector del sistema Android: puede ofrecer Google Drive si está instalado y conectado. KML/KMZ se identifica por sus bytes, porque una URI SAF puede carecer de extensión; ZIP se procesa en QBuffer para proveedores sin seek. «Compartir / Guardar en Google Drive» usa NothingDocuments.open(...,share=true) y NothingFileBridge existente; el usuario elige Drive en el chooser. No se incorporan OAuth, tokens ni un listado privado nuevo de Google Drive. La confirmación final del guardado externo corresponde al proveedor seleccionado. QuickDialogs2 queda explícitamente vinculada al target Mobile.

Servicios Login, Calicatas, Rendiciones, Drive, Supabase, IA, manifest, Java y JNI no tienen cambios. GlassSurface.qml y glass.frag permanecen idénticos al respaldo.

## Evidencia y compilación del usuario

- CTest host: **6/6** (`rp_core`, `rp_provider`, `rp_planet`, `rp_planet_provider`, `rp_geodocument`, `rp_planet_view`). Incluye XML inválido, anillos, KMZ round trip, geometría nativa, import/export del controlador, visibilidad, límites de complejidad, Back, construcción del adaptador y GPS compartido.
- Red real C++: **LIVE_EOX LIMA 2016 256x256 effective_resolution=10m**, proveedor **150 checks** aprobados.
- Script actualizado: **19/19** comprobaciones de fuente y recursos.
- qmllint: sin errores de sintaxis; conserva advertencias de contexto dinámico y tipos InGe.Mobile no disponibles en el proyecto host aislado. El adaptador se construye en la suite QML usando únicamente un fixture de frontera de documentos; no certifica el backend ni permisos Android.
- Captura offscreen host: no produjo una presentación útil del globo y tipografía; no se acepta como validación visual ni se declara PASS_ANDROID.
- Revisión final de código: dos hallazgos de presupuesto y registro corregidos; segunda revisión sin bloqueantes. `git diff --check` sin errores.

Respaldo anterior a toda edición: `C:/Users/PC-02/Documents/InGePlus/_backups/earth_product_20261014_082631_before/`, 1551 archivos, manifest SHA256 y bundle Git.

## Archivos y commits

Modificados: CMakeLists.txt; qml/Mobile/HomeScreen.qml (solo contenedor, Back, estado de cuenta y preset Earth); qml/Mobile/RetroplasmaEarthView.qml; src/retroplasma/CMakeLists.txt, RetroplasmaCamera.h/.cpp, RetroplasmaController.h/.cpp, RetroplasmaPlanetProvider.cpp, RetroplasmaTileScheduler.cpp, RetroplasmaItem.cpp; tests/retroplasma/CMakeLists.txt, planet_provider_tests.cpp, planet_view_tests.cpp; scripts/verify_earth_planetary_static.py.

Nuevos: qml/Mobile/EarthDocumentSheet.qml; src/retroplasma/RetroplasmaGeoDocument.h/.cpp y RetroplasmaGeoController.cpp; tests/retroplasma/geodocument_tests.cpp; este informe y docs/superpowers/plans/2026-10-14-earth-product.md.

Commits funcionales: `67b6cef` (datos/LOD/cámara), `099172b` (geometrías KML/KMZ y herramientas), `b718641` (interfaz fullscreen/adaptador Drive). Documentación y verificador se entregan en un cuarto commit. No se hizo push ni se modificó el historial anterior.

En Qt Creator abrir CMakeLists.txt, seleccionar Qt **6.9.3 Android arm64-v8a** para dispositivo o **x86_64** para el emulador del usuario, conservar INGE_BUILD_MOBILE=ON y target **AppCalicatasMobile**. Ejecutar **Run CMake** para QuickDialogs2, nuevas fuentes y QML; luego **Compilar**. No se necesitan credenciales nuevas ni assets manuales.

Probar: pantalla completa y safe areas; planeta entero inicial y regreso global; zoom y navegación Perú/Lima con red; EOX histórico y fallback sin conexión; GPS/permisos; arrastre/pinch/norte; Back de paneles y retorno a Calicatas; KML/KMZ de puntos, líneas y polígonos; centrar/ocultar/quitar; exportar/reimportar; InGeDrive carpeta/subida/descarga; Google Drive SAF/chooser; cambio de cuenta; memoria y fluidez en dispositivo. Build, instalación, render real y pruebas de nube están pendientes del usuario.

## UX 5.0 · Liquid Glass y Dock contextual (2026-10-14)

Eliminados del visor: la cápsula superior `InGe Earth | Buscar lugar` y la barra inferior Lugares / Medir / Archivos / Info. El globo ocupa toda la pantalla; abajo solo quedan el Dock global y InGe IA. La atribución NASA / USGS · EOX (CC BY 4.0, Copernicus Sentinel 2016) queda en una etiqueta compacta abajo a la izquierda; un toque la amplía y otro abre Capas y fuentes.

Seis controles laterales `EarthGlassAction.qml`, cada uno una instancia de la GlassSurface existente (glass.frag sin cambios) sobre UNA captura del globo a 1/4 + UN MultiEffect compartidos; lente (refracción aproximada) por mapeo de región, sin pasadas extra; borde iluminado, brillo especular y sombra interior pintados una vez en Canvas. Gama LOW/ULTRA_LOW (`dockLowCostGlass`): sin captura, cristal tintado denso. Panel abierto: la columna se retira y la captura queda congelada (`live: false`).

| Control | Acción |
|---|---|
| Brújula | aguja girada con el rumbo real (`cameraInfo.heading`); toque `command("north")`, interpolado por la cámara |
| GPS | `requestGps()` compartido: permiso, búsqueda (anillo), fix (locate-fixed) o fallo/timeout real |
| Capas | panel real `layers` (Sentinel EOX, Blue Marble, Landsat HLS) |
| + / − | `command("zoomIn"/"zoomOut")`, los mismos del Dock; atenuados en 2 km / 50 000 km |
| Centrar | `goTo` de la última selección (GPS, coordenadas, calicata); ya centrado o sin selección: `command("reset")` |

Dock: `DockContextController` admite 8 raíces (kMaxActions); el preset anterior publicaba 15 y perdía Lugares, Info, Capas y GPS. Nuevo preset: Acercar, Alejar, Restablecer vista visibles; `···` = Buscar lugares y coordenadas, Lugares guardados (Sudamérica, Perú, Lima), Archivos KML/KMZ (Importar, Abrir desde InGeDrive, Guardar en InGeDrive, Exportar), Información geográfica, Herramientas (Medir, Fuentes y capas, GPS, Girar, Desplazar, Modo navegación, Coordenadas). La búsqueda encuentra lugares guardados/geometrías KML abiertas y acepta `lat, lon`.

Verificación sin compilar la app: qmllint sin errores (solo advertencias de contexto dinámico ya existentes), `scripts/verify_earth_planetary_static.py` 24/24, arnés `qml.exe` offscreen con un RetroplasmaView simulado (imagen NASA del repo) para cristal, gama baja, GPS buscando y panel de búsqueda, sin avisos QML. No certifica el render QRhi ni Android: build, instalación, logcat y pruebas en dispositivo quedan en Qt Creator.
