# AASHTO gráfico y editor a toda el área

Solicitud: representar AASHTO junto a SUCS en el editor, preview, Excel y PDF; eliminar la cabecera de la ficha. No se compila por instrucción del usuario.

Se añaden 12 SVG rotulados «AASHTO» y su grupo. Son identificadores gráficos de InGe+, no equivalencias ni modificaciones de los símbolos SUCS. GW + A-1-a usa dos bandas; GW-GM + A-1-a usa tres; AASHTO solo también se representa. Las tramas SUCS originales y todos los datos de laboratorio se conservan.

Editor/preview reutilizan el renderer de capas. Excel/PDF comparten exportGraphicBandsFor y webGraphicExportTile: reparten E:I entre 1/2/3 bandas y cargan los mismos recursos QRC. El encabezado del perfil indica SUCS/AASHTO. Falta de SVG o error al rasterizar produce error de exportación; el PDF parcial no se confirma.

El editor deja de reservar 106 dp arriba: se retiran asa, código superior y esquinas de hoja; el fondo y el único ImeAwareFlickable ocupan el área del editor. Se conservan presencia, estado del sistema, teclado y Dock/navegación. El código de la ficha sigue en sus datos y formulario General.

Validación: `node tests/calicatas/aashto_graphics.cjs` pasa composición, recursos, clasificación inalterada y reparto de columnas; `node tests/calicatas/pending_selectors_patterns.cjs` pasa la regresión de adopción. XML de QRC y 12 SVG válido. qmllint de CalicataFormPage.qml sale 0 con avisos de análisis de imports/tipos desde fuente. Sin CMake, build, APK, ADB ni suites completas.

Pendiente: compilar y comprobar legibilidad/tamaño de teselas, 1/2/3 bandas en pantalla y en PDF/Excel reales, teclado, Dock y temas. No se afirma validación visual ni compilación C++.

Se conserva e integra el exportador PDF nativo en curso (calicatawebpagedpdf.inc y su llamada ya estaban en el workspace), necesario para mantener un único recorrido activo de PDF. Sus cambios previos se respaldaron fuera del repositorio. Otros cambios previos de resources.qrc y CMake no se incluyen en este commit.
