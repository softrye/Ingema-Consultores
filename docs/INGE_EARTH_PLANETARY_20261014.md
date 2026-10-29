# InGe Earth Planetario — entrega de fuentes, 14/10/2026

La apertura inicial de Earth está conectada a un **elipsoide WGS84 completo
texturizado con imágenes NASA reales**, dentro del renderer QRhi existente.
La cámara parte desde el espacio y permite navegar hacia Sudamérica, Perú,
Lima, coordenadas WGS84 o el GPS compartido de InGe+.

Estado: **CODE_READY**, **STATIC_PASS** y pruebas host **5/5**.
**PASS_ANDROID pendiente de la prueba visual del usuario.** Esta entrega no
acredita renderizado, GPS físico ni rendimiento en Android. No se compiló
Android, ejecutó ADB ni inició emuladores durante esta corrección.

## Alcance y archivos

Se retomó íntegramente el working tree del checkpoint del 13/10/2026 sobre
`04671e3a93b40148611424b286099e0a0d031227`. El cierre del 14/10/2026 conserva
esa implementación; añade documentación, verificación actual y commits.
No se repitió la construcción del motor ni la investigación/descarga NASA.

| Componente | Archivos en el repositorio | Resultado |
|---|---|---|
| Geometría y cámara | `src/retroplasma/RetroplasmaPlanet.{h,cpp}`, `RetroplasmaCamera.{h,cpp}` | Elipsoide, sectores, UV, precisión, órbita y navegación |
| Datos NASA | `RetroplasmaPlanetProvider.{h,cpp}`, `RetroplasmaScene.h`, `RetroplasmaDataProvider.h`, `resources/earth/` | Base mundial incorporada y mosaicos GIBS/HLS |
| LOD/carga | `RetroplasmaTileScheduler.{h,cpp}`, `RetroplasmaController.{h,cpp}` | Árbol dinámico, cobertura, cancelación, caches y selección de fuente |
| GPU/compilación | `RetroplasmaItem.cpp`, `src/retroplasma/CMakeLists.txt` | Mismo viewport QRhi, luz de visualización, Qt6::Network y recursos QRC |
| Earth/controles | `qml/Mobile/RetroplasmaEarthView.qml`, `HomeScreen.qml` | Planeta inicial, lugares, GPS, fuente/fecha y acciones del Dock existente |
| Pruebas | `tests/retroplasma/CMakeLists.txt`, `planet_tests.cpp`, `planet_provider_tests.cpp`, `planet_view_tests.cpp` | Regresiones planetarias y carga del componente QML |
| Entrega | `scripts/verify_earth_planetary_static.py`, checkpoint, plan y este informe | Evidencia y procedimiento de compilación |

No cambian los archivos de Login, Calicatas, Drive, Supabase, IA, CoreFlow,
Dock global, Deep Press, Quick Bubble, GlassSurface.qml ni glass.frag. Home
solo incorpora las acciones de Earth. También permanecen intactos
`main_mobile.cpp`, el CMake raíz, manifest, JNI/Java y el servicio GPS compartido.
MediaProjection permanece fuera del visor principal; MapLibre no se reactiva
y Cesium conserva su respaldo histórico.

## Sistema geográfico y cámara

El elipsoide usa WGS84: radio ecuatorial 6378137 m y achatamiento derivado de
la matemática WGS84 existente. Los cálculos geográficos y de cámara usan
double/ECEF; las posiciones GPU se expresan en radios terrestres, con el eje
norte hacia arriba. Los sectores se generan en latitud/longitud con UV
equirectangular y normales elipsoidales; la costura ±180° y los polos están
cubiertos. Se conserva una sola cámara lógica y el backend global anterior.

La vista inicial tiene altitud de cámara de 22 millones de metros. La
interpolación conecta la órbita con vistas regionales sin cambiar de visor.
Sudamérica, Perú y Lima tienen destinos predefinidos; «Ir a coordenadas» y
GPS conservan el punto y su altitud. La altitud del objetivo y la distancia
de cámara se muestran por separado. Hay arrastre, zoom, giro de orientación,
norte y regreso al planeta completo. El zoom tiene un mínimo de cámara de
40 km; no se ofrece acercamiento indefinido ni detalle submétrico.

## Imágenes, resolución y cobertura

| Fuente conectada | Cobertura/disponibilidad | Resolución |
|---|---|---|
| Blue Marble incorporada, JPEG 2048×1024 | Toda la Tierra, incluida en QRC; apertura sin Internet | ~19.6 km/píxel ecuatorial en la vista general |
| NASA GIBS `BlueMarble_NextGeneration` | Mosaicos regionales con Internet y disponibilidad del servicio | Dataset nativo 500 m; nuestros sectores de nivel 5 ~611 m/píxel ecuatorial |
| NASA/USGS GIBS `HLS_L30_Nadir_BRDF_Adjusted_Reflectance` | Tierras emergidas según adquisición; cobertura parcial, nubes y huecos | Dataset nativo 30 m; nuestros sectores de nivel 9 ~38 m/píxel ecuatorial |

Blue Marble es una composición satelital, no una fotografía actual ni datos
sintéticos. El JPEG incorporado proviene del WMS oficial GIBS con BBOX mundial
EPSG:4326; su URL, atribución y SHA256 están en
`src/retroplasma/resources/earth/provenance.json`.

SHA256 del JPEG de 209456 bytes:
`7f1b66f435c3a21a3dce6a537818997a28c5a820dd218c45308054daf2eddabd`.
La atribución NASA Earth Observatory / Reto Stöckli y NASA/USGS se muestra
en el visor junto con la resolución cargada, cobertura HLS y fechas reales.

Para HLS se puede indicar una fecha AAAA-MM-DD. Si se deja vacía, se buscan
hasta 16 fechas entre hace 4 y 19 días por sector, con presupuesto de 30 s.
Esto puede producir un mosaico con distintas fechas, mostradas como intervalo;
no constituye una imagen simultánea ni garantiza imágenes libres de nubes.
Cuando faltan datos HLS se mantiene Blue Marble como base identificada.

Las condiciones se verificaron el 13/10/2026: uso factual de imágenes NASA con
atribución y sin sugerir patrocinio; Landsat USGS es de dominio público. No
se incorporaron logos, personas, credenciales ni endpoints privados.
Referencias primarias:
[Blue Marble](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-map/),
[acceso GIBS](https://nasa-gibs.github.io/gibs-api-docs/access-basics/),
[resoluciones GIBS](https://nasa-gibs.github.io/gibs-api-docs/access-advanced-topics/),
[uso de imágenes NASA](https://www.nasa.gov/nasa-brand-center/images-and-media/),
[uso de datos Landsat USGS](https://www.usgs.gov/faqs/are-landsat-data-cloud-still-considered-be-within-public-domain).

## LOD, recursos y límites

La base tiene 32 sectores permanentes (ocho por longitud y cuatro por latitud).
El quadtree solicita mosaicos visibles según frustum/horizonte y tamaño en
pantalla; limita las solicitudes remotas por selección a 96 y la resolución
a los niveles indicados. Los mosaicos se aplican a geometría ECEF curva,
manteniendo la cobertura base debajo de los detalles.

La corrección de la revisión independiente conserva 32 subdivisiones en L0,
igual que la base, y 16 desde L1. Una prueba de intersecciones radiales falló
con la versión anterior y pasó con esta densidad: evita que la curvatura
entierre el detalle L0 bajo la base opaca. Los shells y el recorte de alfa
permiten componer las capas regionales y sus huecos.

Dos trabajadores realizan la carga; las generaciones/cancelación descartan
respuestas obsoletas. Los caches CPU y GPU mantienen presupuestos estimados
de 64 MiB cada uno; el cache de red tiene 128 MiB y acceso serializado. Cada
respuesta está limitada a 4 MiB y cada petición a 15 s, con cancelación
comprobada cada 50 ms. Estos presupuestos no representan la memoria total
del proceso ni mediciones de rendimiento en un dispositivo.

Limitaciones pendientes: confirmación visual y rendimiento Android, GPS real,
cobertura/fecha/nubes de HLS, ausencia de elevaciones DEM y edificios 3D,
ausencia de fotografía urbana submétrica y de protocolos RockTree/CRN. La
superficie actual es el elipsoide WGS84 con imágenes; no fotogrametría urbana.

## Verificación y respaldo

Reconfirmado el **14/10/2026**, sin reconstruir el módulo:

- CTest: **5/5** aprobadas (`rp_core`, `rp_provider`, `rp_planet`,
  `rp_planet_provider`, `rp_planet_view`). La suite planetaria contiene 3316
  comprobaciones. La suite QML verifica carga/registro y propiedad del GPS
  mediante un objeto de prueba; no confirma el hardware GPS.
- Checker planetario: **16/16** comprobaciones de fuentes/recursos aprobadas.
- `git diff --check`: sin errores; únicamente avisos de normalización LF/CRLF.

El 13/10/2026 se compiló el módulo para pruebas host Qt 6.9.3 MinGW, incluidos
moc, registro QML, qsb y rcc. Ese día también se probó el proveedor C++ en vivo:
Blue Marble devolvió datos; un sector de Lima obtuvo HLS con 100% de píxeles
con datos, adquisición 02/10/2026 y ~39.1358 m/píxel entregados. Es evidencia
de descarga/decodificación, no una prueba de calidad visual o render Android.
No se repitieron esas descargas en el cierre del 14/10/2026.

Comandos ejecutados al reanudar:

```powershell
& 'C:/Qt/Tools/CMake_64/bin/ctest.exe' --test-dir 'C:/Users/PC-02/Documents/InGePlus/_backups/earth_planetary_20261013_174351_before/host-build' --output-on-failure
python scripts/verify_earth_planetary_static.py
git diff --check
```

Se usaron los DLL/plugins del kit host `C:/Qt/6.9.3/mingw_64` y MinGW
`C:/Qt/Tools/mingw1310_64`. Las pruebas de red opcionales estaban desactivadas.
El respaldo original verificado permanece en
`C:/Users/PC-02/Documents/InGePlus/_backups/earth_planetary_20261013_174351_before/`
con 1538 archivos, manifest SHA256 y bundle Git. No se modificó ni eliminó.

## Compilar desde Qt Creator

1. Abrir `C:/Users/PC-02/Documents/InGePlus/AppCalicatasDemo/CMakeLists.txt`.
2. Seleccionar **Qt 6.9.3 Android x86_64** para el emulador, o
   **Qt 6.9.3 Android arm64-v8a** para dispositivo. Mantener
   `INGE_BUILD_MOBILE=ON` y el target **AppCalicatasMobile**.
3. Ejecutar **Run CMake / Ejecutar CMake** desde Qt Creator para actualizar
   el módulo, Network y los recursos NASA; después pulsar **Compilar**.
   Los shaders y recursos se generan con CMake. No preparar assets manuales,
   nuevas credenciales, otra APK ni permisos de captura.

Después de compilar, la prueba visual del usuario es abrir InGe Earth desde
Home y comprobar el planeta completo con continentes/océanos. Girarlo,
usar Sudamérica → Perú → Lima, zoom/norte/coordenadas y volver a
«Planeta completo». La base inicial funciona sin conexión.

Para comprobar detalle regional con Internet, abrir el Dock
«Imágenes NASA / escenas» y seleccionar «NASA/USGS Landsat HLS · 30 m»;
dejar la fecha vacía para buscar una adquisición reciente. Revisar la fecha,
cobertura y resolución mostradas. Probar GPS con permiso de ubicación y
verificar salida/reentrada, orientación y regreso a las demás subaplicaciones.
Conservar los datos locales; no desinstalar ni borrar almacenamiento.

Commits de implementación:

- `8928ae9`: motor WGS84, cámara, NASA/GIBS/HLS, LOD, recursos y pruebas de núcleo/proveedor.
- `e40a970`: controles planetarios, integración GPS/Dock de Earth y suites QML/CTest.

El commit siguiente guarda este informe, el checker, el plan completado y el
checkpoint histórico. El historial completo se obtiene con
`git log --oneline 04671e3..HEAD`.
