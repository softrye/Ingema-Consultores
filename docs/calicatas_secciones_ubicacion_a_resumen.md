# Ficha de calicata — secciones de Ubicación a Resumen (inventario desde el código)

Fuente: `qml/Mobile/pages/CalicataFormPage.qml` (FP), `qml/Mobile/lib/CalicataRules.js` (CR), `qml/Mobile/pages/CalicataReview.qml` (RV).
«Obligatorio» = genera un BLOCKER en `validateDocument` (CR:216-296), que bloquea la exportación/aprobación. Lo demás es opcional o un aviso.

## Navegación entre secciones
- 6 etapas, en este orden: General (1) → **Ubicación (2) → Perfil (3+4) → Laboratorio (5) → Fotos (7) → Revisión (9)** (FP:1545-1552).
- Avance: `goNextStage()` (FP:1451-1455), `goPreviousStage()` y gesto de swipe horizontal con previsualización de la etapa siguiente (FP:841-880). Salto directo con `scrollToSection(n)` (FP:1743-1760). La sección 6 (Identidad/logos) abre un popup (FP:1752). Cada incidencia de Revisión lleva a su sección y estrato (FP:1728-1739).
- Las tarjetas de progreso agrupan: Identidad = general+ubicación+identidad; Laboratorio y estratos = perfil+lab; Fotos y resumen = fotos (FP:1644-1646).

## 2 · Ubicación (FP:11197-11677) — «Coordenadas UTM del documento»
- **Tarjeta de mapa** «UBICACIÓN DE LA CALICATA»: muestra el punto y sus datos (FP:11301-11323). Botón «Obtener ubicación GPS» / «Actualizar ubicación» (FP:11377) y estado del GPS (FP:11438).
- Grupo **COORDENADAS UTM** (FP:11451):
  - X UTM (Este), número de coordenada, en m, obligatorio, entre 100000 y 900000 (FP:11461; CR:241).
  - Y UTM (Norte), número de coordenada, en m, obligatorio, entre 0 y 10000000 (FP:11471; CR:242).
  - Z UTM / Cota, número de elevación, opcional; si se rellena, entre -12000 y 10000 (FP:11481; CR:246). Botón «Obtener altitud» (FP:11522).
  - Zona UTM, texto, obligatoria; debe incluir la banda, por ejemplo 18L (FP:11495; CR:244). Debajo, un texto informativo con la zona y el datum que tiene la nube (FP:11535).
  - Además se exige una ubicación válida dentro del rango UTM (CR:240).
- Grupo **SISTEMA GEODÉSICO**: Datum, lista con las opciones WGS84 y PSAD56, obligatorio (FP:11546-11556; CR:245).
- Grupo **REFERENCIA VIAL**:
  - Lado de la vía, lista con Derecho, Izquierdo, Ambos, Eje de vía, Berma derecha, Berma izquierda y Fuera de vía; opcional (FP:11569; CR:808).
  - Progresiva (XX+XXX), solo dígitos con patrón `^\d{2,3}\+\d{3}$`, se normaliza y muestra sugerencias (máximo 100); opcional (FP:11587-11630; CR:814-815, 842).
  - Ubicación / Tramo, texto libre, opcional (FP:11667).

## 3+4 · Perfil (FP:10044-10130 y 12021-13184)
- **Profundidad y agua** (sección 3, FP:10044):
  - Profundidad objetivo (opcional, m) (FP:10062).
  - Nivel freático (m), con la opción «Personalizado» (FP:10085-10112).
  - Reglas: la profundidad final debe coincidir con el final de los estratos (CR:281). Si hay nivel freático, su profundidad debe estar entre 0 y la final (CR:285). Si no se evalúa, sale solo un aviso (CR:286). Ancho y largo deben ser válidos o quedar vacíos (CR:253).
- **Configuración del perfil** (FP:12051-12081): Profundidad total (m), Nivel freático (m) e interruptor «Mostrar nivel freático». Si la profundidad total es menor que los estratos registrados, aparece un aviso (FP:1316).
- **Tipo de excavación**: Cielo abierto u Otro, con un texto «Describe la excavación» (FP:12088-12110).
- **Método de descripción**: SUCS o AASHTO (FP:12117-12130).
- **Plantillas globales** (FP:12150): Carretera, Edificación, Cantera, Ambiental / exploración y Plantilla vacía (FP:1084-1092).
- **Observaciones generales**: texto (FP:12189-12195).
- **Estratigrafía**, lista repetible de estratos (FP:12218-12304):
  - Acciones: Añadir estrato, Insertar, Eliminar, Duplicar y Reordenar.
  - Estado vacío: «Crear primer estrato» y «Usar plantilla global».
  - Menú ⋮ en cada fila (FP:12413).
  - Insertar solo funciona desde el último estrato (FP:1238-1243). Duplicar copia la descripción pero no el intervalo, la muestra ni el laboratorio (FP:1253-1254).
- **Editor del estrato**, en línea y sin hoja modal (FP:12583-13014; FP:1709):
  - Hasta (m), obligatorio: debe superar a Desde en pasos de 0.05 m, sin solapes ni huecos y sin pasar la profundidad total (FP:12656; CR:255-266). Al menos un estrato es obligatorio (CR:255).
  - Símbolo / patrón y Color: solo lectura, vienen de Laboratorio; el color es automático (FP:12675-12688).
  - **Origen del estrato** (FP:12705-12809):
    - Origen geológico: Natural, Antrópico o Mixto / intervenido (FP:1054).
    - Origen natural: Residual, Coluvial, Aluvial, Fluvial, Lacustre, Marino / litoral, Eólico, Glaciar / fluvioglaciar, Volcánico / piroclástico, Orgánico / palustre, Roca meteorizada u Otro (FP:1055-1057).
    - Solo si es Antrópico o Mixto (FP:12737), además:
      - Tipo de relleno (FP:1058-1060).
      - Contexto / procedencia (FP:1061-1062).
      - Control de colocación: Sin control, Parcialmente controlado o Controlado (FP:1063).
      - Compactación: Suelta, Media, Densa o Muy densa (FP:1064).
      - Material matriz (FP:1065).
      - Componentes antrópicos, selección múltiple: Concreto, Ladrillo, Asfalto, Plástico, Vidrio, Metal, Madera, Materia orgánica, Desmonte u Otros; con «Otros» se pide especificar (FP:1066-1067, 12789-12809).
  - **Clasificación geotécnica**: SUCS y AASHTO, solo lectura, «Pendiente de laboratorio» (FP:12818-12845).
  - **Descripción** (FP:12852-12908):
    - Descripción: texto obligatorio (CR:511).
    - Estructura: Homogénea, Heterogénea, Estratificada, Laminada, Lenticular, Fisurada, Masiva o Cementada (FP:1068).
    - Humedad: Seco, Bajo, Medio o Agua (FP:1886).
    - Consistencia / densidad: si es granular, de Muy suelta a Muy densa; si es cohesivo, de Muy blanda a Dura (FP:1070-1071).
    - Estabilidad: Baja, Media, Alta o Muy Alta (FP:1888).
    - Excavabilidad: Rend. bajo, medio, alto o muy alto (FP:1887).
  - **Muestra (opcional)** (FP:12927-12987):
    - Tipo de muestra: —, MA, MS, MI, MW u Otro, que se especifica aparte (FP:1889).
    - Desde (m) y Hasta (m): deben quedar dentro del estrato, con Desde menor que Hasta (CR:272).
    - ID de muestra.
  - **Características adicionales**: interruptor; las opciones son Olor, Materia orgánica, Manchas / contaminación, Presencia de raíces, Vacíos y Otros (FP:13001-13014; FP:1073-1075).
  - Botón «Volver a revisión» (FP:12622).

## 5 · Muestras / Laboratorio (FP:13184-13544; editor de ensayos FP:10130-10700)
- Sin estratos: aparece el texto «Aún no hay estratos para laboratorio» y el botón «Ir a Perfil» (FP:13225-13243).
- Cabecera:
  - Botón «Nueva muestra»: abre la muestra del estrato filtrado o del primero sin muestra; sin estratos lleva a Perfil (FP:13257; FP:248-262).
  - Selector de vista: Estratos y muestras / Resultados (FP:13266).
  - Filtros: Todos (n) / Pendientes (n) / por estrato (FP:13285-13290).
- La lista repetible tiene una tarjeta por estrato con la proyección SUCS/AASHTO y la etapa: Sin datos, Sin ensayo, En proceso, Sugerido o Adoptado (FP:13351-13403; CR:1237).
- **Editor de ensayo por estrato**:
  - Contexto del estrato, en solo lectura (FP:10204-10257).
  - Historial (FP:10268).
  - **Granulometría (MTC E107)**, % que pasa, de 0 a 100: Máx., Nº 4 (4.75 mm), Nº 10 (2.00 mm), Nº 40 (0.425 mm) y Nº 200 (0.075 mm). Cada tamiz debe ser menor o igual que el anterior (FP:10369-10424; CR:762-773).
  - **Plasticidad (MTC E110/E111)**:
    - Límite líquido (WL) y Límite plástico (LP): enteros no negativos, con LP ≤ WL (FP:10436-10448; CR:756-765, 774).
    - Índice de plasticidad (IP): se calcula automáticamente (FP:10454-10462).
  - **Humedad natural (MTC E108)**: en %, hasta 500 (FP:10470; CR:766).
  - **Clasificación sugerida**: AASHTO y SUCS calculados; si faltan datos, «Datos insuficientes» (FP:10504-10548).
  - **Clasificación del laboratorio** (FP:10597-10675):
    - Elegir entre SUCS simple o Clasificación compuesta.
    - SUCS principal y 2.º SUCS: en la compuesta los dos son obligatorios y deben ser distintos (CR:775-777).
    - AASHTO.
  - **Laboratorio / procedencia**: Fecha de ensayo (AAAA-MM-DD, validada) y Laboratorio (nombre) (FP:10682-10698; CR:781).
- El laboratorio solo informa, no bloquea la exportación (CR:323-325, 340-341).

## 7 · Fotografías (FP:11680-12021) — «Cámara y archivos por categoría»
- Tres categorías obligatorias: Zona de ejecución, Interior de calicata y Acopios. Si falta la foto o su archivo, es un BLOCKER (CR:288-292).
- Tarjeta vacía con el texto «Sin fotografía — Toma o adjunta una foto para esta categoría» (FP:11871-11879). Se marca «Original conservada» cuando hay una foto anotada (FP:11966).
- Acciones del menú: Importar de galería o Reemplazar desde galería, cámara y editar (FP:2600-2611). El editor de anotación está en `CalicataPhotoEditor.qml` (FP:3132-3135).

## 8 · Observaciones / Actividad (FP:13544-13684)
- Actividad: eventos confirmados en la nube, con el botón «Cargar más» (FP:13544-13579).
- Observaciones: texto libre «Escriba observaciones generales...» y el botón «Volver a revisión» (FP:13586-13612).

## 9 · Revisión final / Resumen (`CalicataReview.qml`, 889 líneas)
- Estado de la calicata (RV:229).
- **Resumen de la calicata** (RV:373-404): mosaicos que llevan a su sección.
  - Profundidad total.
  - Fotografías: X / 3.
  - Ubicación, con el datum.
  - Suelo predominante, con su espesor.
  - Nivel freático.
- **Perfil estratigráfico**: vista gráfica con leyenda por estrato (RV:413-511).
- **Rendimiento de excavación** (RV:535-631):
  - Excavabilidad.
  - Volumen excavado (L × A).
  - Duración, calculada con las fechas de inicio y fin.
  - Excavabilidad y estabilidad predominantes.
  - Riesgo operativo.
- **Completitud por componente**: % de requisitos cumplidos (RV:643; CR:323-366).
- **Análisis y conclusiones**:
  - Botón InGe AI, para una revisión asistida que necesita al menos un estrato (FP:486).
  - «RESUMEN DE LA FICHA», generado sin inferencias, y recomendaciones (RV:716-820).
  - «Editar observaciones» (RV:882).

## Notas
- La sección 3 tiene dos implementaciones de profundidad y agua (FP:10044 y FP:12051). No comprobé cuál se ve en el teléfono.
