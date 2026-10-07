# Corrección post QA de Calicatas

Cambios en fuente, sin compilación Android, ADB ni commit por instrucción expresa.

- Entrada: ocultación del empty state y cabecera durante inicialización automática.
- Dock: referencia explícita al editor ligada a su ciclo de vida. Evita consultar
  propiedades y métodos de la página anterior del Loader durante la transición.
  Perfil añade la acción existente de estratos; fotos usa cámara/adjuntar existentes.
- Atrás: el editor consume navegación interna antes de la salida a Home.
- Fechas: MonthGrid y DayOfWeekRow de Qt Quick Controls 6.9.3, fecha completa,
  cancelar/aceptar; sin reglas nuevas entre fechas.
- Identidad: modal con logos predeterminados físicos del exportador, selección
  desde Recursos y picker personalizado, conservando paths/persistencia existentes.
- Ubicación: instancia modal del MapPageContent 2D existente, selección táctil y
  aceptación explícita protegida por UUID de documento. Se quitaron enlaces a Earth
  y aplicación automática del GpsBus al abrir/cambiar ficha. El GPS sirve para centrar.
- Perfil: se conserva el registro vacío interno por compatibilidad y se oculta
  hasta edición/confirmación. El límite de 3 m está también en el validador C++ del
  exportador (androidcalicataexporter.cpp); se conserva y etiqueta como límite del
  formato actual. La profundidad objetivo opcional deja de derivarse automáticamente.
- Fotos: tres miniaturas y selector de las tres categorías reales; acciones en dock.
- Revisión: círculo con número real de bloqueos o LISTO, filas compactas y
  actualización diferida reactiva; sin porcentaje ficticio ni botón grande de refresh.

Referencia Nothing: carpeta DOCUMENTOS inspeccionada, licencia GPLv3 de Nothing
Files revisada; no se copió código externo. Se adaptaron los principios visuales
y tokens propios de flutter/inge_earth/lib/renditions/v3/theme/rendition_theme.dart,
usando el catálogo de iconos existente. No se modificó Renditions ni Documents.

Validación: qmlcachegen focal de Main, editor, formulario, revisión y mapa PASS;
qmllint ejecutado, con avisos de objetos C++/imports de aplicación no resolubles
fuera del runtime. Se corrigió la limitación del import Controls 2.15 para calendario.
git diff --check focal PASS. No se ejecutó qmlformat, build, instalación ni logcat.

Pendiente: confirmar en teléfono ausencia de los tres warnings de dock, regreso
desde estrato, calendario, logos, toque/aceptación de mapa, borrador y exportación.
La verificación estática no sustituye esa prueba física. MapPageContent ya tenía
cambios del usuario al empezar; se conservaron y se añadió un modo de selección.
No se cambiaron plantilla, exportador, clasificadores ni esquema de datos.
