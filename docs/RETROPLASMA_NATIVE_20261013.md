# InGe Earth Retroplasma Native — entrega de fuentes

Estado: **CODE_READY / STATIC_PASS**. La revisión final no ejecutó CMake,
compiladores, herramientas Qt de generación, APK, ADB, instalación ni emuladores.
La compilación y ejecución Android quedan a cargo del usuario. No se declara
PASS_BUILD, PASS_ANDROID, rendimiento satisfactorio ni regresión Android aprobada.

## Implementación e integración

El módulo `src/retroplasma` contiene matemática WGS84/ECEF/ENU en double,
cámara única con interpolación, decodificadores OBJ y BC1, proveedor local,
árbol espacial con hasta ocho hijos por nodo, selección progresiva por error
en pantalla, controlador asíncrono y renderizador QRhi mediante QQuickRhiItem.
Incluye shaders propios y un terreno sintético CC0 texturizado: cinco nodos,
diez mallas OBJ en dos niveles de detalle y una textura PNG original.

El renderizador crea VBO, IBO UInt16, texturas RGBA, sampler, uniformes y
pipelines con prueba/escritura de profundidad. Descarta nodos por frustum;
conserva la cobertura del padre mientras se cargan los hijos visibles. El
reemplazo GPU se confirma solo cuando todos los recursos nuevos están listos;
si falla una asignación, se conserva el último conjunto dibujable y se muestra
el error. «Reintentar escena» permite recargar explícitamente el mismo paquete.
Qt administra superficie, contexto EGL y composición dentro de la misma APK;
las operaciones GPU ocurren en el hilo de render de Qt. La sincronización
transfiere instantáneas desde el controlador. No hay JNI ni superficie externa
nueva. Se conserva la selección global existente: OpenGL ES en Android y
selección de Qt en escritorio. Se enlazan Quick, Concurrent, ShaderTools y
GuiPrivate; esta última API está acotada al renderizador y a Qt **6.9.3**.

`main_mobile.cpp` publica una instancia `EarthNative`; el módulo registra
`RetroplasmaView` mediante qt_add_qml_module. CMake enlaza módulo y plugin
estáticos e incorpora `qml/Mobile/RetroplasmaEarthView.qml`.
Home mantiene la navegación desde Calicatas y conecta el Dock actual a zoom,
rotación/inclinación, desplazamiento, norte, vista inicial, coordenadas, modo
navegación, métricas y selección de escena local. Un dedo orienta o desplaza;
dos dedos desplazan, giran y hacen zoom. La telemetría no regenera el Dock.

Los permisos, servicio y hooks exclusivos de captura se retiraron del manifest
y de InGeQtActivity. El prototipo FusionBridge se conserva íntegro en
`labs/fusionbridge-historical`, fuera de las fuentes Java/QML/CMake activas.
Cesium y los servicios Android compartidos permanecen intactos. Se mantiene
Flutter como dependencia de los servicios compartidos de biometría/Rendiciones;
no se utiliza como superficie del nuevo visor. No se reactiva MapLibre.

## Datos, recursos y licencias

La lectura de metadatos/mallas/texturas se realiza en un pool de dos trabajadores,
con cancelación y revisión de generación antes de aceptar respuestas. Las caches
CPU y GPU tienen un presupuesto separado de 64 MiB; los recursos fuera de
selección se liberan. Cada tile está limitado a 32 MiB, la textura final a
1024 por dimensión, el manifest a 128 nodos y seis LOD por nodo. Las mallas
de más de 65535 vértices únicos deben dividirse en nodos. Si la transición con
la cobertura anterior no cabe, se conserva esa cobertura y se informa
RP_CPU_TRANSITION_MEMORY_LIMIT o RP_GPU_TRANSITION_MEMORY_LIMIT sin expulsar y
recargar hermanos repetidamente. El límite es de caches/recursos estimados,
no de la memoria total del proceso ni de los temporales de decodificación.

Se soportan OBJ con XYZ, UV, normales explícitas o calculadas, índices negativos
y triangulación en abanico de polígonos convexos; PNG/JPEG mediante QImageReader
y DDS DXT1/BC1 sin mipmaps mediante expansión CPU a RGBA. QImage se usa solamente
para decodificar y subir texturas; los frames se dibujan con GPU. Los formatos o
recursos inválidos producen códigos RP_/OBJ_/BC1_ recuperables. Al salir se
cancelan cargas, se vacían caches y se destruye el viewport; los recursos GPU
se reconstruyen ante cambios de contexto/render target o generación de escena.

El formato propio `inge-retroplasma-scene-v1` admite `title`, `source`, `license`,
origen WGS84 y nodos con bounds/LOD. Los XYZ y bounds usan **este, norte, arriba**
en metros respecto al origen; el motor transforma a **este, arriba, -norte**.
Los bounds son `[emin,nmin,umin,emax,nmax,umax]`; las rutas mesh/texture son
relativas al manifest. `error` se expresa en metros y decrece con cada LOD.
Los hijos reemplazan al padre completo: la unión de sus bounds debe cubrir el
del padre; el proveedor rechaza cobertura parcial con RP_CHILD_COVERAGE_INCOMPLETE.
El archivo `src/retroplasma/resources/sample/scene.json` es el ejemplo completo.

La escena incorporada es terreno **sintético CC0**, georreferenciado cerca de
Lima; no representa datos medidos ni imágenes/fotogrametría de Google.
El Dock «Escena local» permite cargar un scene.json y sus assets desde una
ruta accesible a la app, o recargar la escena incorporada. No necesita servidor,
credenciales ni permisos de captura para abrir el contenido incorporado.

Se auditó el ZIP original sin modificarlo, incluyendo Flycam, rocktree_*,
Protobuf, SDL, Eigen y Crunch. Al no existir una concesión clara para el núcleo
original, no se copió su código ni esquema RockTree; las implementaciones son
propias. No se añadieron SDL/Eigen/Protobuf/Crunch ni endpoints privados de Google.
La auditoría y las licencias examinadas están en `RETROPLASMA_AUDIT_20261013.md`.
La arquitectura usa las interfaces oficiales
[QQuickRhiItem](https://doc.qt.io/qt-6/qquickrhiitem.html) y
[QRhi](https://doc.qt.io/qt-6/qrhi.html).

Limitaciones concretas: **NOT_IMPLEMENTED** para semántica Protobuf RockTree,
contenedor CRN, fuentes remotas y selector SAF `content://`. El proveedor actual
es local/qrc; no ofrece cobertura planetaria ni acceso a Google Earth. La
precisión de transformaciones geográficas es double, pero cada paquete de
escena usa un origen local y bounds limitados a 100 km por eje. No se declara
renderizado planetario completo. FPS mide presentación Qt y el tiempo CPU
mide registro de comandos; no se presenta como medición de tiempo GPU.

## Validación de esta entrega

`python scripts/verify_retroplasma_static.py`: **21 comprobaciones aprobadas**:
registro/enlace y fuentes, mismo launcher/controlador, backend conservado,
contrato de shaders, índices/límites, diez mallas con bounds/UV/winding válidos,
CRC y píxeles PNG, cámara, gestos, Dock, coordenadas relativas, jerarquía/LOD,
presupuestos y recursos, cancelación/ciclo de vida, alcance protegido y retiro
de captura; incluye protecciones de transición CPU/GPU, cobertura completa y
recorte de texels transparentes BC1. Es inspección de fuentes/recursos, no
ejecución del renderer. La revisión independiente identificó los tres casos de
cobertura/admisión, corregidos en fuentes antes de la entrega. Se añadieron
casos de regresión de proveedor/scheduler; no se ejecutaron por la restricción.

Se contrastaron las APIs y señales usadas con los headers instalados de
Qt 6.9.3 para Android x86_64 y arm64-v8a, y se verificó la disponibilidad de
ShaderTools en ambos kits. `git diff --check` verifica el diff final.
Login, Supabase, AuthSession, Calicatas, InGeDrive, IA, CoreFlow, Dock/DeepPress/
QuickBubble, GlassSurface.qml, glass.frag y el respaldo Cesium no tienen cambios
de código. Home solo cambia la integración de Earth y el cierre de su sesión.

Antes de la orden «no compiles», se ejecutó una build host del núcleo inicial
y su módulo Qt: CTest **2/2** (matemática/decodificadores y proveedor/LOD), con
compilación de shaders y registro QML. Esa evidencia corresponde a una revisión
anterior: **los cambios finales de controlador, renderer e integración no han
sido compilados**. Las pruebas fuente permanecen en `tests/retroplasma`.

Respaldo reversible previo: `C:/Users/PC-02/Documents/InGePlus/_backups/retroplasma_native_20261013_before/`,
con 3648 archivos, manifest SHA256 y bundle Git; base `7fd2027`.

Commits por componente:

- `5c9a43a`: auditoría, derechos y diseño.
- `01fd124`: núcleo matemático/gráfico, cámara y decodificadores.
- `f92169d`: proveedor local y escena CC0.
- `faadf61`: carga asíncrona, LOD y transiciones CPU/GPU seguras.
- `e563dca`: integración Home/Dock y retiro de captura del empaquetado activo.

El commit posterior de documentación/verificación contiene este informe y el
checker. El historial completo se consulta con `git log --oneline 7fd2027..HEAD`.

## Compilación a cargo del usuario

1. Abrir el CMakeLists.txt raíz de AppCalicatasDemo en Qt Creator.
2. Usar el kit **Qt 6.9.3 Android x86_64** para tu emulador, o **arm64-v8a**
   para dispositivo; conservar INGE_BUILD_MOBILE=ON y target AppCalicatasMobile.
3. Dejar que Qt Creator regenere CMake por los cambios de módulo/QML/shaders
   y pulsar **Compilar**. Usar un directorio de build nuevo para esta revisión
   evita residuos de las clases Java históricas en android-build. No se necesita
   preparar manualmente código, shaders ni recursos del nuevo módulo.

Después de compilar, la comprobación Android consiste en abrir Earth y observar
el terreno texturizado, probar gestos y comandos Dock, abrir coordenadas y la
fuente local, salir/volver, pasar a segundo plano/cambiar orientación y revisar
las métricas/errores. Probar regreso a Calicatas, multicuenta, Login, Home, Drive,
IA, Dock/QuickBubble y exportaciones verifica la regresión en el dispositivo.
No desinstalar ni borrar datos como parte de esta actualización.
