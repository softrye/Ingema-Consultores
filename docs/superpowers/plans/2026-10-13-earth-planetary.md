# Corrección InGe Earth planetario

Objetivo autorizado: abrir Earth con el planeta mundial real texturizado,
extender el QRhi existente y conservar las demás subaplicaciones. Ejecución
directa y secuencial; pruebas host permitidas, Android/ADB prohibidos.

Diseño: geometría WGS84 en ECEF double, render en radios terrestres para evitar
float32 de millones de metros, sectores lon/lat con normales elipsoidales y
UV equirectangular. Una sola Camera soporta órbita planetaria y escenas locales.
El planeta base NASA Blue Marble queda incorporado en QRC y visible sin red.
El mismo proveedor agrega GIBS WMS EPSG:4326 por sectores y HLS Landsat a 30 m
como capa regional de cobertura parcial/fecha explícita. La cobertura base
permanece bajo los mosaicos; no se ocultan ausencias ni se inventa detalle.

Archivos: RetroplasmaPlanet.{h,cpp} (geometría/sectores); Camera (órbita),
Scene/DataProvider y nuevo PlanetProvider (contenido NASA y red limitada),
TileScheduler (quadtree planetario dinámico), Controller/Item (carga/render),
RetroplasmaEarthView.qml/HomeScreen.qml (GPS/Dock y fuentes), CMake/resources,
tests/retroplasma y checker estático. No cambiar backend global ni servicios GPS.

- [x] Pruebas host de elipsoide, polos/costura, UV, winding, órbita y Lima.
- [x] Geometría/cámara planetaria y pruebas unitarias.
- [x] Fuente NASA incorporada, licencia/atribución, proveedor GIBS/HLS.
- [x] LOD dinámico, cobertura continua y caches/cancelación existentes.
- [x] Navegación global/Perú/Lima/GPS y Dock existente (fuentes y pruebas host).
- [x] Verificación estática, revisión final, commits e informe Qt Creator.

Reanudación 14/10/2026: working tree conservado sobre `04671e3`;
CTest 5/5 y checker 16/16 reconfirmados, sin reconstruir el motor. Se conserva
la revisión independiente del 13/10/2026 y su fix L0 verificado RED→GREEN.
El cierre conserva la auditoría, las descargas y la revisión ya terminadas;
la ejecución Android sigue pendiente de la prueba visual del usuario.

Commits de implementación: `8928ae9` (motor/datos), `e40a970` (controles/pruebas).
La documentación, el checker y este plan se guardan en el commit de cierre.

Evidencia/instrucciones: `docs/INGE_EARTH_PLANETARY_20261014.md`.
Los checks anteriores acreditan fuentes y pruebas host, no PASS_ANDROID.
- [ ] Prueba visual/GPS/rendimiento Android a cargo del usuario tras compilar.

Presupuestos: tiles 256x256, máximo 96 hojas de detalle por selección,
cache CPU y GPU 64 MiB cada una, cache de red 128 MiB, dos trabajadores.
Blue Marble nativa 500 m; overview 2048x1024 aproximadamente 19.6 km/píxel
ecuatorial; Landsat HLS 30 m nativa, no imágenes urbanas submétricas.
