# InGe+ — Calicatas Ubicación: mapa estable y edición en fullscreen

**Corte:** 2026-11-04 · Rama: codex/fusionbridge-native · Qt 6.9.3 / Android

## Límites de la intervención
Se leyeron AGENTS.md y el handoff. No se compiló, no se instalaron APK, no hubo commits y no se editaron HomeScreen/Dock, Auth, Login, Supabase backend, Rendiciones ni exportadores PDF/XLSX. Se preservaron los archivos compartidos/untracked y los datos existentes.

## Causas verificadas en fuente y cambios
1. CalicatasTopoMap.qml (~67, ~106–125, ~300): running dependía de visible y del estado Qt.ApplicationActive; el Loader permanecía activo por everActive, manteniendo mapas ocultos vivos. Ahora el Map QtLocation sigue únicamente el active de la página y el tamaño del componente. Se retiraron los manejadores que reescribían center/zoom/bearing cada vez que el motor los notificaba; la cámara se aplica imperativamente. Ya no hay zoom de teselas animado por fotograma. OpenTopoMap y caché no cambiaron.
2. CalicatasHome.qml (~1088–1100): el Map del Home estaba activo debajo de la ficha y sufría scale dinámico. Ahora sólo vive en el modo Home con vista mapa, y su superficie no se reescala.
3. CalicataUbicacionView.qml (~124, ~215, ~289): el Map de la tarjeta sólo está activo en sección 2/fullscreen. Cámara inicial por documento; ya no se recentra al recibir cada nuevo objeto de point durante autosave. Se añadió resumen no editable de referencia vial.
4. CalicataMapEditor.qml (~28, ~64, ~115, ~365, ~570, ~615): conserva una sola instancia Map por reparent al terminar Hero; la devuelve antes del Hero inverso. No usa capas de blur, shape punteado ni escala/compás reactivos. Dos botones inferiores GPS/teclado, píldora de coordenadas tocable y un botón Fijar ubicación. La hoja de edición es scrollable y acepta UTM, zona+banda, datum, cota, Obtener altitud, lado, progresiva y tramo. Demora cualquier cambio de documento hasta commitLocation y protege documentId.
5. CalicataFormPage.qml (~840, ~1539, ~10765–10860): sección 2 cerrada sólo muestra tarjetas, coordenadas e indicadores. Todos los campos previos se editan en la hoja fullscreen, usando los setters antiguos, documento existente, validación y autosave/LIVE. Al cambiar de ficha, rechaza guardar el borrador equivocado. Validación de candidato antes de mutar. Conserva Z ingresada si se fijó desde mapa o desde hoja.
6. CalicatasEditorPage.qml (~1090, ~1706): la acción mapa va al mismo editor fullscreen, evitando crear otro QtLocation. Navegación next/previous se difiere al evento siguiente para que el contexto del Dock no incremente generación durante el toque.
7. permissionhelper.cpp (~1356, ~1385, ~1437): Android emitía fixes brutos en ráfagas pese a interval=1500ms; el log registra sólo una muestra cada 100 y QML recibe publicaciones con separación >=1000ms, salvo solicitud puntual. Cuando el usuario está quieto se renuevan timestamp y precisión cada segundo sin mover coordenadas, evitando falso GPS stale. Deadband original 2.5m intacto.

## Zona y banda
El valor legado '18' se transforma usando la E/N de la MISMA calicata: Rules.utmToGeoForDatum(E,N,'18',datum), que interpreta zona numérica como hemisferio sur, seguido de Rules.geoToUtmForDatum(lat,lon,datum) para calcular la banda (por ejemplo 18L). Si falta E/N válida, conserva '18' como valor inválido visible para corregirlo; no inventa banda a partir del centro por defecto del mapa. El menú permite 17K/L/M, 18K/L/M, 19K/L/M y el documento mantiene nombres de campo existentes.

## Diagnósticos
INGE_CALICATA_MAP_ACTIVE running=... active=... size=...
INGE_CALICATA_MAP_CAMERA_SET reason=explicit zoom=...
INGE_CALICATA_MAP_HERO_READY single_engine=1
INGE_CALICATA_MAP_EDITOR_OPEN mode=...
INGE_CALICATA_MAP_ELEVATION ok=1|0
INGE_CALICATA_MAP_COMMIT mode=... road=1
INGE_CALICATA_MAP_DOCUMENT_COMMITTED mode=...
INGE_CALICATA_MAP_COMMIT_REJECTED reason=document_changed|invalid_point
INGE_CALICATA_MAP_COMMIT_FAILED
INGE_CALICATA_MAP_EDITOR_CLOSED

## Validación estática
- node tests/calicatas/location_map_performance_contract.cjs: 18/18 PASS.
- qmllint Qt6.9.3 con --ignore-settings --import disable --unqualified disable --missing-type disable en 6 QML: código de salida 0. El analizador aún emite avisos de tipos dinámicos de mapa y Qt.
- git diff --check: 0 en archivos rastreados (sólo avisos LF/CRLF).
- NO compilado, NO medido FPS, NO verificado visualmente ni corrido en Android. El objetivo de 60 FPS no se puede certificar con pruebas estáticas.

## Riesgos y QA pendiente del usuario
1. Un emulador Android x86_64 GLES y proveedor OpenTopoMap remoto puede impedir 60 FPS aun con UI estabilizada. Medir gesto de pan/zoom con teselas calientes y frías; contar creaciones QtLocation al pasar Home↔Ficha.
2. El reparent después del Hero puede causar un fotograma vacío por reasignación de superficie; comprobar en Qt Android.
3. Comprobar a teclado abierto la hoja de edición: scroll, E/N, zona 18L, datum WGS84/PSAD56, cota DEM/manual, lado de vía, progresiva, tramo, fijar y reabrir. Comprobar que la Z automática no se convierta indebidamente en manual.
4. El Dock real (HomeScreen.qml) no se editó. El contexto fullscreen se dejó independiente para evitar STALE; hay que confirmar visualmente si el Dock global queda encima y diseñar ocultación mediante el shell sólo con autorización.
5. Logcat del usuario muestra dos aborts nativos SIGABRT std::bad_alloc en Qt JNI/QJniObject::getCachedMethodID durante QGuiApplication::applicationStateChanged. No se ha demostrado que sean causados por el mapa. Pendiente simbolizar tombstone contra APK exacto; no declarar resuelto.
6. `Qt.ApplicationActive` ya no destruye el Map en permisos GPS; Qt suspende su render al perder EGL. Confirmar que se recupere tras pausa/resume y que no flapee.
7. No se cambió el PDF, Excel, Auth, Supabase, Rendiciones ni la vista global Dock; no se hicieron commits.

## Pruebas a ejecutar tras compilación por el usuario
Home lista: sin Map activo. Home mapa: sólo su Map. Abrir una ficha: Home Map liberado. Stage Ubicación: un Map activo. Expandir: Hero sin escalado GPU por frame. Pan/zoom: sin oscilaciones ACTIVE/LEVEL. Abrir hoja y guardar todos los campos. Alternar tabs y reabrir: verificar aislamiento de documentos, autosave y presencia. Verificar botón siguiente/anterior sin INGE_DOCK_STALE. Validar GPS permiso/reanudación y tombstone nativo por separado.
