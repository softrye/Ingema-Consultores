# AASHTO gráfico y editor sin cabecera

Objetivo autorizado: dibujar AASHTO junto a SUCS en editor, preview, PDF y Excel; retirar cabecera/asa y márgenes superiores del editor. Sin compilar ni ADB.

Diseño: teselas SVG rotuladas «AASHTO» y su código, con fondo claro translúcido, como identificación gráfica propia de InGe+. No se atribuyen símbolos SUCS a un grupo AASHTO. Un SUCS + AASHTO = dos bandas; SUCS compuesto + AASHTO = tres. Clasificaciones y almacenamiento no cambian. Se reutiliza el renderer de capas QML y un reparto único de columnas para PDF/Excel.

- [x] Recursos de los 12 grupos AASHTO, QRC y pruebas puntuales.
- [x] Proyección gráfica QML con bandas SUCS/AASHTO y textos claros.
- [x] Exportación nativa con la misma composición; error si falta una tesela.
- [x] Editor sin cabecera, asa, hueco superior ni esquinas de hoja; conservar Dock, presencia, IME y un solo scroll.
- [x] qmllint, pruebas puntuales, documentación y commit; validación real pendiente del usuario.

Los archivos del exportador y resources.qrc tenían cambios previos. Se respaldan fuera del repo y se conserva el exportador PDF nativo en curso; no se modifican otras funciones ni se usa el exportador legado como fallback.

Código y pruebas puntuales preparados. La compilación, exportación real y validación visual quedan pendientes del usuario.
