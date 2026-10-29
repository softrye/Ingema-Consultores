# Checkpoint — InGe Earth planetario — 2026-10-13

> Registro histórico del 13/10/2026. El usuario reanudó el 14/10/2026;
> el cierre actualizado está en `docs/INGE_EARTH_PLANETARY_20261014.md`.
> Los estados «sin commits» y «detenido» del cuerpo describen esa pausa.

**Trabajo detenido por orden del usuario:** «detetnte mañana continuamos arma
un log de checkpoint porfavor nada mas». Solo se guarda este checkpoint.
No continuar implementación, pruebas, compilaciones ni commits hasta que el
usuario reanude. No se programó ninguna ejecución automática.

## Objetivo vigente

Corregir la entrega anterior: abrir InGe Earth con la Tierra completa WGS84,
continentes/océanos e imágenes NASA reales, cámara orbital, navegación a Perú/
Lima/coordenadas, GPS compartido y Dock existente. Extender el renderer QRhi
actual dentro de la misma APK. El terreno sintético no es la escena inicial.

Android/ADB/emuladores están prohibidos; el usuario compila Android desde Qt
Creator. En esta nueva solicitud autorizó pruebas unitarias host. Preservar
Login, Calicatas, Drive, Supabase, IA, Deep Press, Quick Bubble, GlassSurface.qml,
glass.frag, backend global y servicios compartidos. No reactivar captura,
MapLibre ni Cesium como motor principal.

## Git y respaldo

- Proyecto: `C:/Users/PC-02/Documents/InGePlus/AppCalicatasDemo`.
- HEAD: `04671e3a93b40148611424b286099e0a0d031227`.
- Los cambios planetarios están **en el working tree, sin commits nuevos**.
  Conservarlos; no resetear, restaurar ni sobrescribir fuentes.
- Respaldo verificado anterior a los cambios:
  `C:/Users/PC-02/Documents/InGePlus/_backups/earth_planetary_20261013_174351_before/`.
  Incluye 1538 archivos Git, manifest SHA256 y `history.bundle`.
- Plan: `docs/superpowers/plans/2026-10-13-earth-planetary.md`.
  Sus checks aún requieren actualizarse al cerrar la entrega.

## Implementación actual en fuentes

- `RetroplasmaPlanet.{h,cpp}`: elipsoide WGS84/ECEF double, posiciones GPU
  normalizadas al radio ecuatorial, sectores lon/lat, UV, normales, winding y
  visibilidad por frustum/horizonte. La costura de ±180° cierra.
- `RetroplasmaCamera.{h,cpp}`: una única cámara con modo planetario; órbita
  inicial a 22 millones de metros, aproximación continua a superficie,
  navegación geográfica, zoom mínimo de 40 km, giro de orientación y norte.
- `RetroplasmaPlanetProvider.{h,cpp}`: proveedor extendido del módulo existente,
  32 sectores de base mundial incorporada, GIBS WMS EPSG:4326 y Landsat HLS L30.
  La base mundial permanece visible bajo los mosaicos regionales.
- `RetroplasmaTileScheduler.{h,cpp}`: quadtree dinámico, hasta 96 solicitudes
  remotas por selección; Blue Marble hasta nivel 5, HLS hasta nivel 9, con
  límites de resolución y cobertura base permanente.
- `RetroplasmaController.{h,cpp}`: apertura inicial `inge-earth://global`,
  selección de imágenes/fecha, cámara preservada al cambiar proveedor,
  comandos Sudamérica/Perú/Lima y atribución/resolución/fechas/cobertura visibles.
- `RetroplasmaItem.cpp`: luz de visualización orientada hacia la cámara
  planetaria; misma integración QRhi y contratos de buffers/shaders.
- `RetroplasmaScene.h`, `RetroplasmaDataProvider.h`, CMake del módulo: nuevos
  datos de sectores/procedencia y dependencia Qt6::Network; recursos NASA en QRC.
- `qml/Mobile/RetroplasmaEarthView.qml`: controles planeta/Sudamérica/Perú/Lima/
  GPS, giro con pinch, fuente NASA y fecha HLS. Se usa el servicio `Perms`
  existente; se libera solo tracking iniciado por Earth, respetando otro cliente.
- `qml/Mobile/HomeScreen.qml`: acciones Earth GPS/lugares/fuentes en el Dock
  existente; ningún cambio global al Dock ni a los servicios GPS.

## Fuente NASA y resolución

Archivo: `src/retroplasma/resources/earth/blue-marble-global-2048.jpg`.
JPEG real de 2048x1024, 209456 bytes, descargado del servicio oficial NASA GIBS
con `BlueMarble_NextGeneration`, BBOX global y proyección geográfica.
SHA256: `7f1b66f435c3a21a3dce6a537818997a28c5a820dd218c45308054daf2eddabd`.
URL y atribución están en `resources/earth/provenance.json`.

La vista general incorporada entrega aproximadamente 19.6 km/píxel ecuatorial;
el dataset Blue Marble es de 500 m nativos y los mosaicos regionales de esta
implementación llegan aproximadamente a 611 m/píxel. HLS Landsat es de 30 m
nativos y los sectores de nivel 9 entregan aproximadamente 38 m/píxel ecuatorial.
HLS tiene cobertura parcial, fechas y nubes; no ofrece detalle submétrico de
edificios. Su ausencia deja visible la base NASA, con cobertura/resolución
efectiva declaradas.

Red: managers en trabajadores, pool de dos, acceso al cache de disco serializado,
128 MiB de cache, respuesta máxima de 4 MiB, deadline de 15 s por petición y
cancelación cada 50 ms. La fecha automática busca hasta 16 fechas entre hace
4 y 19 días, con presupuesto total de 30 s por tile. La fecha real cargada
se conserva y se muestra. Los caches CPU/GPU existentes son de 64 MiB cada uno.

Referencias verificadas:

- https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/base-map/
- https://nasa-gibs.github.io/gibs-api-docs/access-basics/
- https://nasa-gibs.github.io/gibs-api-docs/access-advanced-topics/
- https://www.nasa.gov/nasa-brand-center/images-and-media/
- https://www.usgs.gov/faqs/are-landsat-data-cloud-still-considered-be-within-public-domain

Se verificaron condiciones de uso factual con atribución NASA y sin sugerir
endorsement; Landsat USGS es de dominio público. No se incorporaron logos,
personas, credenciales ni servicios privados.

## Evidencia obtenida antes de detenerse

**No se compiló Android ni se ejecutó ADB. No declarar PASS_ANDROID.**

Build host Qt 6.9.3 MinGW del módulo y pruebas, incluidos moc/qmlregistrar/qsb/
rcc, completada. Directorio fuera del repositorio:
`../_backups/earth_planetary_20261013_174351_before/host-build`.

Última ejecución CTest: **5/5 suites aprobadas**, cero fallos:

1. `rp_core`: matemáticas/decodificadores anteriores.
2. `rp_provider`: escena local/LOD y regresiones anteriores.
3. `rp_planet`: 3316 comprobaciones de WGS84, polos, UV, winding, costura y cámara.
4. `rp_planet_provider`: JPEG NASA real, mundo offline, LOD/GIBS, coordenadas
   Lima/Londres/Tokio/Sídney/polos/antimeridiano y regresión de profundidad L0.
5. `rp_planet_view`: creación QML/tipo nativo/gestos y GPS mediante objeto de
   prueba; liberar tracking propio y conservar tracking previamente activo.

Consulta adicional en vivo usando el proveedor C++ en un trabajador:

- Blue Marble: 100% de píxeles con datos, resolución reportada 500 m.
- Landsat para un sector de Lima: 100% de píxeles con datos, resolución
  entregada 39.1358 m/píxel, adquisición **2026-10-02**, obtenida por búsqueda
  automática. Es evidencia de descarga/decodificación, no de render Android.

`python scripts/verify_earth_planetary_static.py`: **16 comprobaciones aprobadas**.
`git diff --check`: sin errores de whitespace; solo avisos Git LF/CRLF.
No se ha medido rendimiento ni producido una captura del globo desde Android.

## Revisión independiente y corrección final

La revisión de lectura `earth_planetary_review` terminó; no queda trabajo
delegado en marcha. Detectó un defecto P2: remoto L0 de 16 subdivisiones podía
quedar enterrado bajo overview de 32 por la curvatura y el depth-write.

Se añadió `PlanetSceneProvider::geometryFor()` y una prueba de intersecciones
radiales con puntos interiores: falló con la geometría anterior y pasó tras
usar **32 subdivisiones en L0** y 16 desde L1. La última ejecución 5/5 CTest
y el checker estático corresponden a esta corrección aplicada.

La revisión no encontró otros problemas importantes; no acredita renderizado
ni funcionamiento GPS real en Android.

## Al retomar, pendientes concretos

1. Leer este checkpoint y revisar Git, conservando el working tree actual.
2. Completar informe de entrega planetaria: archivos, fuentes/licencias,
   resolución/cobertura, cámara/LOD, limitaciones y pasos Qt Creator.
3. Actualizar checks del plan y crear commits por componentes funcionales.
   Hasta ahora no hay commits planetarios posteriores a `04671e3`.
4. Hacer únicamente la verificación final apropiada si cambia código.
5. Entregar al usuario el procedimiento de compilación de AppCalicatasMobile
   con Qt 6.9.3 Android; la confirmación visual y PASS_ANDROID son del usuario.

No iniciar automáticamente esos pasos. El pedido actual termina guardando
este log y dejando todo detenido para la próxima reanudación.

## Reanudación y cierre — 14/10/2026

El usuario reanudó explícitamente. Se leyó completo este registro y se
conservaron los cambios descritos. Las suites CTest se reconfirmaron 5/5 y
el checker planetario 16/16, utilizando el build host existente; no se
reconstruyó el motor ni se repitieron las descargas NASA.

La implementación se guardó en `8928ae9` (motor/datos planetarios) y `e40a970`
(controles Earth/GPS y pruebas). Se completó la documentación y el plan;
el commit de cierre incluye este registro histórico y el checker.

La guía vigente es `docs/INGE_EARTH_PLANETARY_20261014.md`. Queda a cargo del
usuario compilar AppCalicatasMobile desde Qt Creator con Qt 6.9.3 Android y
confirmar la imagen del planeta y el GPS real. No se declara PASS_ANDROID.
