# Extensión global del Liquid Glass existente — 2026-10-01

## Alcance y causa

Las superficies secundarias no reutilizaban todos los tokens y el shader del Dock. FlowGlassSurface conserva su fallback y ahora admite LiquidGlassSurface solamente en grupos enfatizados, visibles, en reposo y con un fondo separado seguro. Main publica el material del Dock en el único InGeCoreFlow. No se altera el Dock.

InGeDrive reutiliza el componente en búsqueda, menú contextual y diálogo. Perfil reutiliza su fondo compuesto para el grupo principal. Search aprovecha el backdrop QML cuando es seguro; los fondos nativos parciales o ancestros conservan el fallback. Ajustes mantiene sus superficies FlowGlassSurface existentes.

Home Flutter añade el InGeGlassSurface existente a la cápsula de perfil y dos controles de cabecera. Rendiciones v3 lo añade a NothingHeading. Cada página comparte un InGeGlassBackdrop estático, sin capturas de filas ni del contenido durante scroll. La opción adicional enabled conserva true por defecto para los consumidores existentes y evita cargar/capturar el shader en las nuevas superficies cuando el perfil exige fallback.

Calicatas, Auth/Login y Earth mantienen sus tratamientos existentes. En Earth se conserva el fallback seguro para la composición nativa/Impeller/Cesium. No se modifica lógica funcional, navegación, datos, Supabase, bridges ni animaciones.

## Presupuesto y límites

QML: capturas locales congeladas del mismo fondo, seis muestras como máximo y dos en bajo coste; se desactiva el efecto durante movimiento, reduceMotion y Earth. Flutter: una captura compartida por página con el límite existente de 1.25 de pixelRatio; cuatro muestras por superficie, sin sombras adicionales ni velo. Los botones y las filas conservan sus estados y callbacks. No se ha medido FPS ni memoria en Android.

## Verificación estática real

Se ejecutaron las herramientas nativas mediante Node spawnSync para capturar de forma fiable su salida en Windows. No se generaron scripts de solución ni se modificaron las herramientas del proyecto.

```text
C:/Qt/6.9.3/mingw_64/bin/qmllint.exe --json - qml/Mobile/flowcore/FlowGlassSurface.qml qml/Mobile/Main.qml qml/Mobile/GlobalSearchOverlay.qml qml/Mobile/documents/NothingDocumentsRoot.qml qml/Mobile/flowcore/InGeCoreFlow.qml
```

Resultado: exit 0, sin errores de sintaxis. Los JSON mantienen success=false por avisos existentes de imports/metadatos/tipos del proyecto. Avisos por archivo: 5, 1548, 36, 185 y 4, respectivamente. Los primeros cuatro se compararon con los archivos originales de esta sesión: cero mensajes nuevos. Los cuatro avisos de InGeCoreFlow no apuntan a la propiedad añadida. No se generaron metadatos mediante build ni se silenciaron categorías.

Desde flutter/inge_earth:

```text
C:/Users/PC-02/Develop/flutter-3.44.9/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/home.dart lib/home_final.dart lib/inge_liquid_glass.dart lib/renditions/v3/components/nothing_components.dart
```

Resultado: exit 2, cero errores y un warning unused_element_parameter para selected en home.dart:2823. El mismo warning fue comprobado en el archivo original de la sesión. No se corrige código ajeno al alcance para ocultarlo.

git diff --check: sin errores. Los hashes de GlobalContextDock.qml, LiquidGlassSurface.qml y qml/Mobile/shaders/liquidglass.frag coinciden con el inicio de la sesión. No se creó ni editó ningún shader. Imports y referencias reutilizan los recursos existentes.

No se ejecutaron CMake, Gradle, compilación, APK, instalación, ADB ni escrituras remotas. La compilación manual y las pruebas visuales/performance quedan a cargo del usuario conforme a su petición. No se declara validación completa de runtime ni análisis estático limpio.

## Git y trabajo previo

La fase modifica nueve archivos fuente existentes y crea este informe; no elimina archivos. El árbol ya contenía cambios extensos anteriores. La aplicación parcial de los cambios a HEAD fue evaluada en un índice temporal, sin modificar el índice real ni el working tree: Main, FlowGlassSurface, InGeDrive y Home dependen del estado fuente previo y producen conflictos contra HEAD. El commit por archivos conserva ese estado anterior en los archivos seleccionados; los demás cambios previos permanecen fuera del commit. inge_liquid_glass.dart ya existía al iniciar la tarea, aunque Git todavía no lo había registrado. El diff exclusivo de esta sesión es la extensión visual descrita arriba.

Estado: implementación en fuente cerrada; validación parcial por los avisos estáticos previos y las pruebas manuales pendientes.
