# Recursos SUCS del preview InGe+

27 códigos usados por la app: 15 bases y 12 combinaciones (GM-GC conserva el orden alternativo). Relleno antrópico es un material especial separado; RE/RA son identificadores de recurso, nunca clasificaciones SUCS. PT se normaliza a Pt.

Fuente contrastada visualmente el 2026-09-23: MTC 2014, Cuadro 4.4, página impresa 32 (PDF 33).
https://portal.mtc.gob.pe/transportes/caminos/normas_carreteras/MTC%20NORMAS/ARCH_PDF/MAN_7%20SGGP-2014.pdf
La página de referencia se conserva en MTC_Cuadro_4_4_PDF33.png.

Los SVG son redibujos monocromáticos transparentes de los signos: GW óvalos huecos; GP fragmentos llenos; GM/SM verticales con granos llenos/huecos; GC/SC diagonales con granos llenos/huecos; SW/SP puntos de tamaños variados/uniformes; ML/MH verticales; CL/CH diagonales; OL verticales continuas/discontinuas; OH diagonales continuas/discontinuas; Pt ondas horizontales. La densidad de línea es una adaptación legible, no una dimensión normativa.

Las combinaciones son composiciones InGe+ de las bases, mitad izquierda/derecha sin estiramiento ni divisor agregado. No se atribuyen como figuras individuales al MTC. RE/RA comparten la misma trama suplementaria. No confundir OH con relleno: el origen y el código SUCS son datos independientes.

Los PNG 256 son derivados actualizados; usar SVG en producción. Los SVG no tienen texto, fondo, borde externo ni degradado. El QRC del paquete resuelve rutas relativas reales. El catálogo se regenera desde esos mismos vectores.

Integración: AppCalicatasDemo/SUCS/mtc es una copia autocontenida; el QRC registra /SUCS/mtc. Los recursos antiguos usados fuera del preview se conservan. CalicataProfile usa una sola escala lineal, profundidad real y edición existente. Las tarjetas delgadas se desplazan hacia abajo para que quepa todo el texto; la columna y las cotas nunca se estiran por tarjeta. El Flickable existente desplaza todo conjuntamente.

Verificación solicitada: solo estática, sin compilar ni ejecutar la app.
