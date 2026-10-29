# Auditoría Flycam y diseño InGeRetroplasma

Base InGe+: `7fd2027`. Ejecución directa/secuencial autorizada por la solicitud.
Respaldo: `../_backups/retroplasma_native_20261013_before`, 3648 archivos con
SHA-256 verificado, manifest y history.bundle. No se compila Android ni usa ADB.

ZIP original intacto: `C:/Users/PC-02/Documents/inge earth/earth-reverse-engineering-master.zip`.
SHA-256: `f302f970a4c42e5b3dabe7a23d8147f05e65f13907187f53a6d798bbdccc1270`.
Extraído fuera del proyecto en `inge earth/audit-retroplasma-20261013` (57 entradas).

## Código auditado

| Archivo | Arquitectura real observada | Adaptación propia |
|---|---|---|
| client/main.cpp | SDL, contexto GL2.1/ES2, shader transform/UV/máscara octante, cámara ECEF double, velocidad por altitud, near/far por horizonte, traversal/culling/LOD | Qt Quick RHI, cámara WGS84 double y origen ENU local |
| rocktree_gl.h | VBO de vértices compactos, IBO uint16 triangle strip, RGB/JPEG y S3TC DXT1; abort en formatos/errores | Buffers float relativos + índices uint32, RGBA8 portátil, errores recuperables |
| rocktree_decoder.h | Delta XYZ, UV modular, varints/triangle strips, normales empaquetadas, octant masks | Decodificador propio OBJ y BC1/DXT1; frontera para protocolos; no copiar algoritmos particulares |
| rocktree_math.h | Frustum por planos y OBB, perspectiva y lookAt double | Matemática general reimplementada y testeada |
| rocktree_types.h | Bulk/nodos con octree, epochs, OBB, meshes y estados atómicos; handles GL en la estructura | Manifest local, árbol espacial, LOD por error de pantalla, recursos GPU separados |
| rocktree_util.h | Protobuf generado, pools de red/decodificación, callbacks y selección de textura | Proveedor local asíncrono separado del renderer |
| rocktree_http.h | HTTP/fetch contra servicios privados de Google y cache | No portar endpoint ni transporte privado |
| proto/rocktree.proto | Schema proto2 de metadatos, solicitudes, mallas y texturas | No copiar schema sin permiso claro; no afirmar soporte semántico RockTree |
| client/build.sh | g++ C++14, pkg-config SDL2/Protobuf, Eigen, GL/glad/GLEW, crn; rama Emscripten | CMake Qt6.9.3 y ShaderTools, sin SDL/GL de escritorio |
| .gitmodules | Eigen submódulo | Matemáticas propias, no dependencia Eigen |

## Licencias

El ZIP no contiene LICENSE/COPYING general. El README tiene una cláusula de
exclusión de garantía, sin concesión general explícita. **No se copia Flycam,
rocktree_* ni rocktree.proto.** Componentes propios a partir de conceptos
generales, sin traducción línea por línea. Dependencias originales: SDL2 zlib,
Eigen MPL2, Protobuf BSD; derechos de versiones exactas requerirían sus avisos
si se incorporaran. No se incorporan esas dependencias en V1.

stb_image/http tienen licencias permisivas internas; crn_decomp.h incluye aviso
zlib completo al final. No se incorporan en V1: imágenes mediante Qt, BC1 propio;
CRN y RockTree semántico quedan pendientes. No hay autorización de contenido
Google por el hecho de conocer el protocolo.

## Diseño seleccionado

Qt Quick 3D no está instalado en el kit. QQuickRhiItem existe desde Qt6.7 y
está presente en los headers Qt6.9.3. Android ya fija OpenGL en main_mobile.cpp;
no cambiarlo. QQuickRhiItem comparte QRhi/contexto/hilo con Qt Quick y compone
su textura GPU con el Dock. QRhi es API con compatibilidad limitada: fijar
Qt6.9.3 y enlazar GuiPrivate. No crear EGL/SurfaceView ni hilo Android adicional.
Qt gestiona contexto, render target, resize y pérdida de scene graph.

Pipeline propio: shaders GLSL450 empaquetados con qsb (GLSL ES100/300, GLSL120/150,
SPIR-V/HLSL/MSL), depth test/write, VBO/IBO/texturas, culling y bounds.
QImage se usa únicamente para DECODIFICAR texturas, nunca para generar frames.

Geografía WGS84/ECEF en double; ENU relativo al origen de escena para GPU.
Una sola cámara lógica por sesión; interpolación de navegación en el núcleo,
sin añadir sistema de animaciones de UI. Dataset inicial local autorizado,
generado expresamente y rotulado como terreno sintético georreferenciado.
No simula imágenes Google ni cobertura planetaria.

Interfaz del proveedor: manifest JSON con origen WGS84, nodos padre/hijos,
bounds ENU y LODs con error geométrico, archivo OBJ y textura PNG/JPEG/DDS BC1.
Lectura en pool de dos trabajos, cancelación por generación, cache CPU/GPU
acotadas. No URLs remotas ni permisos nuevos. Qt Quick Dialóg/FileDialog no es
necesario para el motor: se acepta una ruta local explícita para paquetes completos.

FusionBridge queda histórico fuera de la compilación/navegación principal;
retirar instancia/proveedor Qt, hooks Activity, FGS/queries/permisos añadidos.
Mantener archivos fuente para reversión y Cesium inactivo.

Fuentes: [repositorio original](https://github.com/retroplasma/earth-reverse-engineering),
[QQuickRhiItem](https://doc.qt.io/qt-6/qquickrhiitem.html),
[QRhi](https://doc.qt.io/qt-6/qrhi.html). Contratos corroborados con headers
locales de Qt6.9.3; no usar métodos posteriores a esa versión.
