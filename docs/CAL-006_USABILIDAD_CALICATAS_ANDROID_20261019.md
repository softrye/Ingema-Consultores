# CAL-006 — Evaluación autónoma de usabilidad de Calicatas Android

- **Fecha:** 2026-10-19, 10:05–10:47 (hora del dispositivo)
- **Dispositivo:** Samsung Galaxy A12 (SM-A127M), 720×1600, Android, app `com.ingema.ingeplus`, compilada e iniciada por la usuaria desde Qt Creator
- **Ficha de prueba:** `CAL-UX-TEST-20261019` · proyecto **«Proyecto de prueba InGe+» (ING-2026-001)**
- **Rol del evaluador:** QA/UX autónomo. No se modificó código, QML, JS ni Supabase. No hubo build, instalación ni commit.
- **Método:** capturas `adb screencap` + toques/teclas `adb input`, interpretando solo lo que muestra la pantalla. El logcat se consultó **después** de terminar el llenado, solo como evidencia del guardado.

---

## 1. Resultado general

**Críticamente incómoda.**

- Llenar la ficha en sí resultó **incómoda**: hubo 18 fallos de interacción registrados, en su mayoría porque el teclado reaparece solo y deja el campo enfocado oculto.
- El veredicto sube a **crítico** por el ciclo de guardado. Tras unos 35 minutos de trabajo, la ficha **no se pudo recuperar** después de cerrar la app:
    - El botón de guardar está escondido a tres niveles.
    - La sincronización fue rechazada 160 veces sin ningún aviso en pantalla.
    - Al reabrir, la app creó una ficha nueva y vacía en un proyecto real.

## 2. Completitud final

**80 %**, según la propia pantalla Revisión (la ficha llegó a ese estado, pero luego no se pudo recuperar).

| Componente | % | Motivo de lo que falta |
|---|---|---|
| Datos generales | 100 % | — |
| Ubicación | 100 % | Coordenadas UTM **manuales de prueba**. El GPS no se obtuvo (ver P1-03). |
| Perfil | 100 % (en naranja) | Falta «Nivel freático no evaluado»: no hay forma clara de marcar «no encontrado» (ver P1-08). |
| Laboratorio | 33 % | Ensayo ficticio solo en E2 (SM / A-2-4). E1 es relleno y queda «No determinado», como pedía el guion. En E3 decidí no cargar ensayo para no alargar la prueba. |
| Fotos | 0 % | No concedí el permiso de cámara y no importé imágenes, para no fabricar evidencia. |
| Identidad | 100 % | — |

## 3. Tiempos

Los tiempos incluyen la latencia del evaluador (≈10–13 s por acción con captura). Un usuario humano tardaría menos en términos absolutos, pero las **proporciones** entre secciones y la cantidad de reintentos sí son representativas.

| Sección | Inicio–fin | Duración | Observación |
|---|---|---|---|
| General | 10:05–10:10 | ~5 min | 3 reaperturas del teclado tras cerrar diálogos |
| Ubicación | 10:10–10:14 | ~4 min | ~1 min perdido en el GPS sin resultado |
| Perfil (3 estratos) | 10:14–10:28 | **~13,5 min** | La sección más costosa: ≈4 min por estrato |
| Laboratorio (E2) | 10:28–10:36 | ~8 min | La hoja se deforma al abrir el teclado |
| Fotos | 10:36–10:38 | ~2 min | Bloqueado por el permiso |
| Revisión | 10:38–10:39 | ~1,5 min | Clara y útil |
| Guardado y recuperación | 10:39–10:47 | ~8 min | **Fallida** |
| **Total** | 10:05–10:47 | **~42 min** | — |

**Interacción aproximada:**

- ≈210 toques, ≈25 desplazamientos y ≈10 confirmaciones con Intro.
- ≈177 capturas de pantalla.
- **22 intentos fallidos o repetidos**: 18 registrados como FAIL más 4 reintentos de botones que no respondieron.

## 4. Problemas identificados (por gravedad)

Tipos: **DF** = defecto funcional · **UX** = dificultad real de usabilidad · **PERM** = requiere datos o permisos que no estaban disponibles en la prueba.

### P0 — Bloquean el uso en campo o causan pérdida de datos

| ID | Tipo | Problema | Evidencia | Justificación |
|---|---|---|---|---|
| P0-01 | DF | **La ficha no se recupera tras cerrar la app.** Al relanzar, Calicatas abre una «NUEVA CALICATA» vacía. `CAL-UX-TEST-20261019` no aparece en «Calicatas abiertas», en InGe Drive ni en «Calicatas online del proyecto». | 10:44–10:47. Logcat tras relanzar: `[M09] create tab … instanceId=0f99…`, sin restaurar `2fc412de…` | Se perdieron unos 35 min de trabajo de campo. **No pude verificar** si el borrador existe en el almacenamiento local: la APK no es *debuggable* y `run-as` falló. Si existe, el defecto es que la interfaz no ofrece cómo abrirlo. |
| P0-02 | DF + PERM | **La sincronización fue rechazada 160 veces sin aviso.** Cada autoguardado y cada «Guardar» terminó en `INGE_CALICATA_SYNC_REJECTED code=42501`. La interfaz solo muestra «Guardar · Pendiente». | Logcat 10:37–10:42: 161 BEGIN y 160 REJECTED | `42501` es *insufficient_privilege* de Postgres: la cuenta probablemente no tiene permiso de escritura en ING-2026-001 (RLS). El permiso puede ser legítimo; el defecto es el **silencio**: el ingeniero cree que guardó. |
| P0-03 | UX | **«Guardar» está escondido a tres niveles:** `⋯` → «Calicatas abiertas» (un nombre que no sugiere guardar) → «Guardar · Pendiente». No hay botón de guardar en la barra. | 10:39–10:41 | Sin entrenamiento no se encuentra. Yo lo encontré después de salir de la app. |
| P0-04 | DF | **El botón «Atrás» de Android desde la ficha cierra la app sin confirmar**, aunque haya cambios sin guardar. | 10:40 | Combinado con P0-01 y P0-03, provoca la pérdida de datos. |
| P0-05 | DF | **El teclado reaparece solo después de cada selector o diálogo** (fecha, maquinaria, tipo, datum, lado, desplegables de estrato) y devuelve el foco al último campo de texto. | 7 veces en la prueba. A las 10:07, la hora se escribió en «Nombre corto»; a las 10:24, la descripción de E3 acabó dentro de «Hasta (m)» | Es la causa raíz de la mayoría de los errores de escritura y de los «saltos» de desplazamiento. Ocurre en todas las secciones. |

### P1 — Dificultan mucho el trabajo o generan datos erróneos

| ID | Tipo | Problema | Justificación |
|---|---|---|---|
| P1-01 | UX | **El campo enfocado queda oculto bajo el teclado** (Nombre del proyecto, X UTM, descripción de estrato, Laboratorio). No hay desplazamiento automático. | Se escribe a ciegas y hay que verificar después. |
| P1-02 | DF | **La hoja de Laboratorio se deforma al abrir el teclado**: la mitad inferior queda en negro (de forma transitoria) y los campos cambian de posición. Un valor de Nº 200 cayó en Nº 40 (`60.00625`). | Riesgo de cargar resultados de ensayo en el tamiz equivocado. |
| P1-03 | DF + PERM | **«Obtener ubicación GPS» abre un mapa en blanco** con el texto «El mapa de InGe Earth está disponible en Android» (estando en Android). «Mi ubicación» tarda ~25 s y termina en «Se requiere permiso de ubicación precisa», **sin pedir el permiso** ni ofrecer ir a Ajustes. | La captura GPS es el flujo principal en campo. La falta del permiso es del entorno, pero no pedirlo y el mapa vacío son defectos. |
| P1-04 | DF | En el estrato, **«Hasta (m)» no se confirma** al cerrar el teclado ni al tocar otro control; solo se confirma con Intro. El resumen mostraba «0,00 – — m». | Hay riesgo de perder profundidades. |
| P1-05 | DF | **«Hasta (m)» acepta texto libre** (campo numérico). | Origina datos inválidos cuando el foco queda mal colocado (ver P0-05). |
| P1-06 | UX | **El botón flotante de InGe IA ocupa la esquina** donde está la tecla de ocultar el teclado: abrí el panel por accidente, y al tocar la X el toque atravesó el panel y abrió «Excavabilidad». | Los toques accidentales cambian datos o la navegación. |
| P1-07 | UX | **Los menús flotantes no responden al primer toque:** «Agregar estrato» falló 2 de 2 veces y `⋯` falló 3 veces. Además, algunos toques **atraviesan** hacia el contenido de detrás. | Se pierde la confianza en los botones; se duplican toques. |
| P1-08 | DF + UX | **Nivel freático:** no existe la opción «No encontrado». Tocar «Personalizado» abrió una hoja «Estrato 2» **en blanco**. Lo escrito en Observaciones no cuenta para la validación. | Impide llegar al 100 % de Perfil en una calicata sin agua, que es el caso más común. |
| P1-09 | UX | Al reabrir la app, la ficha nueva se crea en **CHIVAY (un proyecto real)** por defecto. | Riesgo de crear registros en un proyecto real por error. |
| P1-10 | UX | **Perfil y Laboratorio se envían el usuario de uno a otro:** tocar SUCS en un estrato salta a Laboratorio, y «Registrar muestra» devuelve a Perfil. | Se pierde la posición y hay que volver a desplazarse. |

### P2 — Fricción, claridad y estética

| ID | Tipo | Problema |
|---|---|---|
| P2-01 | UX | Cada estrato pide ~10 controles: origen, tipo o material, descripción, humedad, consistencia, estabilidad, excavabilidad, muestra… y casi todos son selectores modales de un solo valor. |
| P2-02 | UX | Etiquetas crípticas: «Rend. bajo/medio/alto», «MA/MS/MI/MW» sin descripción, «Contrato de laboratorio válido». |
| P2-03 | UX | «Consistencia» mezcla en una sola lista de 11 opciones los términos de suelos granulares (densidad relativa) y cohesivos (consistencia). |
| P2-04 | UX | Las sugerencias SM y A-2-4 **se adoptan tocando el chip**, pero nada indica que sea pulsable; lo descubrí por azar. Tampoco hay un botón «Adoptar sugerencia». |
| P2-05 | UX | Los iconos de la barra inferior no tienen etiqueta (✓, documento con flecha, capas, `⋯`). |
| P2-06 | UX | El menú «glass» tiene texto blanco sobre fondo claro: contraste muy bajo. |
| P2-07 | UX | En Revisión dice «Faltan 1 elemento» y «Pendientes (1)», pero lista **2** pendientes. |
| P2-08 | UX | El ID de muestra es «M-02» en Laboratorio y «…-M2» en Perfil. |
| P2-09 | UX | La hoja «Profundidad y agua» tiene otro estilo: etiquetas truncadas y el botón «Listo» recortado. |
| P2-10 | UX | Al validar la UTM aparece un banner mientras se escribe, que desplaza el diseño ~90 px. Además, «Y» aceptó 11 dígitos. |
| P2-11 | UX | «Plantillas globales» (Carretera, Edificación…) no explica qué hace ni si sobrescribe datos. |
| P2-12 | UX | «Profundidad total» es editable en Perfil, pero en General aparece como «derivada de los cortes». |
| P2-13 | UX | Tocar el cuerpo de la tarjeta de estrato en Laboratorio no la abre; solo funciona el chevron. |

## 5. Acciones que más tiempo consumieron

1. **Recuperar el guardado:** unos 8 min y no se resolvió.
2. **Estratos:** ≈4 min y ≈30 toques por estrato, por la cadena de selectores modales y la reapertura del teclado después de cada uno.
3. **Granulometría y Atterberg:** cada valor exige tocar, escribir, confirmar y esperar a que la hoja se reacomode (~5 s); «Sig.» no mantiene el teclado abierto.
4. **Corregir texto escrito en el campo equivocado** (P0-05): unas 5 correcciones.
5. **Esperar al GPS** sin resultado: ~1 min.

## 6. Dónde me confundí

- Dónde guardar. No asocié «Calicatas abiertas» con guardar.
- Si los datos estaban guardados: «Borrador · Solo en este equipo» no indica la hora del último guardado.
- Qué hacía «Obtener ubicación GPS» (abre un mapa en lugar de capturar).
- Por qué SUCS/AASHTO del estrato no son editables (vienen de Laboratorio) y por qué tocarlos cambia de sección.
- Cómo indicar «sin nivel freático».
- Cómo adoptar la clasificación sugerida.
- «Abrir…» lleva al árbol corporativo de InGe Drive y no a mis borradores.

## 7. Flujo observado frente a flujo ideal de campo

| Paso | Observado | Ideal |
|---|---|---|
| Inicio | Ficha nueva en el último proyecto (puede ser real) | Elegir proyecto o continuar el último borrador local, con un aviso visible |
| Identificación | 6 campos más 3 selectores; el teclado reaparece tras cada selector | Código autogenerado editable; fecha y hora actuales por defecto; responsable = usuario |
| Ubicación | El GPS abre un mapa vacío; luego, entrada manual | Un botón «Capturar GPS» que pide el permiso, muestra la precisión y rellena UTM, zona y cota; la entrada manual como alternativa |
| Estratos | Formulario largo por estrato (~30 toques) | Fila rápida «Hasta / descripción / chips de humedad-compacidad»; los detalles opcionales se despliegan |
| Agua | No se puede expresar «no encontrado» | Tres opciones: *No encontrado · Encontrado a ___ m · No evaluado* |
| Laboratorio | Se carga en campo en una hoja que se deforma | Separado del flujo de campo (normalmente se carga días después), con «Adoptar sugerencia» explícito |
| Fotos | Permiso pedido sin explicación | Explicación previa al permiso; tomar varias fotos seguidas por categoría |
| Guardado | Escondido; fallos silenciosos; «Atrás» sale de la app | Guardado local automático e independiente de la nube, con indicador «Guardado 10:41 ✓», confirmación al salir y estado de sincronización con su motivo |
| Recuperación | Imposible desde la interfaz | Al abrir Calicatas: «Continuar CAL-UX-TEST-20261019 (borrador local, 80 %)» |

## 8. Propuesta para reducir pasos, toques y desplazamientos

1. **No devolver el foco a un campo de texto al cerrar un diálogo o selector.** Corrige P0-05, P1-01 y la mayoría de los FAIL. Se estima una reducción de 30–40 % en toques de corrección.
2. **Mostrar siempre el campo enfocado sobre el teclado** (desplazamiento automático) en todas las hojas, incluida Laboratorio.
3. **Botón «Guardar» visible en la barra** e indicador de estado permanente (*Guardado local · hora* / *Sincronizado* / *Error: sin permiso en proyecto*).
4. **Confirmar los valores numéricos al perder el foco**, no solo con Intro.
5. **Chips en lugar de selectores modales** para listas cortas (humedad 5, estabilidad 3, excavabilidad 3, origen 3). Ahorra 2 toques y un diálogo por campo; con 5 campos por estrato son ≈10 toques por estrato.
6. **Valores por defecto heredados del estrato anterior** (humedad, origen) y «Duplicar estrato».
7. **Alejar el botón flotante de InGe IA** de la zona del teclado, o esconderlo mientras el teclado esté abierto.

**Estimación del flujo ideal** para una calicata de 3 estratos sin laboratorio: **~60–80 toques y 6–8 min**, frente a ≈170 toques y ~25 min observados para General + Ubicación + Perfil.

## 9. Recomendaciones de rediseño

- **Separar «Ficha de campo» de «Laboratorio».** En campo: identificación, ubicación, estratos, agua y fotos. Laboratorio, en un modo posterior.
- **Estrato en dos niveles:** una línea esencial (intervalo, descripción, chips clave) y un panel «Más detalles» desplegable.
- **Navegación:** pestañas con nombre (General · Ubicación · Perfil · Fotos · Revisión) en lugar de flechas «‹ ›» e iconos sin texto; mantener la posición al cambiar de sección.
- **Glosario integrado:** textos completos (*Muestra alterada (MA)*, *Excavabilidad: rendimiento alto*).
- **Listas dependientes del tipo de suelo:** compacidad si es granular, consistencia si es fino.
- **Revisión:** cada pendiente debe llevar directamente al campo; corregir el contador; la hoja de nivel freático debe usar el sistema visual común.
- **Ciclo de datos:** autoguardado local con confirmación visible; errores de sincronización explicados; restaurar el borrador al relanzar; **nunca crear la ficha por defecto en un proyecto real**.

## 10. Veredicto

**Los reportes de la ingeniera y de la gerenta Paola quedan RESPALDADOS por la prueba.**

Respuesta al criterio final: **No.** Hoy un ingeniero **no puede** rellenar una calicata completa en InGe+ de forma rápida, intuitiva y segura sin capacitación:

- **Rápida:** no. Unos 13 min solo para 3 estratos, con 22 intentos fallidos.
- **Intuitiva:** no. El guardado, el nivel freático, la adopción de la clasificación y el GPS no se descubren.
- **Segura:** no. Los datos se escriben en campos equivocados, los fallos de sincronización son silenciosos, «Atrás» sale sin confirmar y la ficha no se recuperó.

**Puntos fuertes que conviene conservar:**

- Progresiva autoformateada («12+500»).
- «Desde» del estrato y el ID de muestra se calculan solos.
- Teclado numérico en las dimensiones.
- Clasificación SUCS/AASHTO sugerida en vivo con explicación.
- La pantalla Revisión: perfil gráfico, completitud por componente, conclusión sin inferencias.
- Mensaje claro de «Selección cancelada» en Fotos.

**Prioridad recomendada:** P0-01 a P0-05 antes de cualquier rediseño visual. Los cambios del punto 8.1–8.4 son de bajo alcance y de alto impacto.

---

## Notas de método y efectos de la prueba (transparencia)

- **Artefacto de la herramienta:** algunas pérdidas de valores en Laboratorio (Nº 10, Nº 200, LL) ocurrieron al inyectar texto con `adb input text` justo después de que la hoja se redimensionara. Con las teclas en pantalla los valores se guardaron. **No se reportan como defecto.** También retiré el hallazgo inicial «el campo Laboratorio no conserva texto», que resultó ser un refresco tardío de la vista. Las reaperturas del teclado (P0-05) **sí** son de la app: se ven en las capturas sin que hubiera ninguna inyección previa.
- **Permisos:** el diálogo de cámara de Android se cerró con «Atrás», así que Android lo cuenta como **denegado una vez**. El permiso de ubicación precisa no estaba concedido. No modifiqué ajustes del sistema.
- **InGe IA:** el panel se abrió una vez por accidente (P1-06); no interactué con él.
- **Proyectos reales:** no se abrió ni modificó ninguna ficha existente. La ficha vacía que la app creó al relanzar (en CHIVAY) se cambió al proyecto de prueba antes de buscar el borrador; **no tiene datos y no se guardó**. Queda abierta en memoria como «Sin guardar 1».
- **Logcat:** solo se leyeron líneas de guardado y sincronización, filtradas para excluir tokens o claves. No hay crash ni ANR de InGe+ en el búfer de fallos durante la prueba.
- **No verificado:** si el borrador existe en el almacenamiento local (la APK no es *debuggable*), y si `42501` se debe a la configuración del permiso de la cuenta o a una política RLS defectuosa. Para cerrar este punto conviene revisar con la usuaria los permisos de su cuenta sobre ING-2026-001.
