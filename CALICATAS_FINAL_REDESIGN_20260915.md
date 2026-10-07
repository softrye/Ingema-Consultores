# Calicatas: rediseño progresivo en fuente

## Alcance y causa

El formulario activo presentaba ocho tarjetas plegables y repetía los editores
de todos los estratos, con un perfil que sólo enumeraba texto. Ahora usa cinco
etapas: General, Ubicación, Perfil, Fotografías y Revisión. La ruta real sigue
siendo `Main.qml → CalicatasEditorPage.qml → CalicataFormPage.qml`.
`Phase54CalicataOverview.qml` no está instanciado por esta ruta y no se modificó.

- Navegación libre y Anterior/Siguiente, con commit de campos y flush del
  autosave antes del cambio. Un valor inválido impide abandonar su contexto.
- General conserva proyecto, código, fechas, supervisor y maquinaria. Logos
  siguen accesibles mediante Identidad del reporte. Lado de vía, progresiva
  y tramo se trasladaron a Ubicación, sin duplicar campos.
- Ubicación conserva captura GPS, UTM, cota y zona. Abre el mapa existente y
  conserva la acción de centrar la coordenada registrada en InGe Earth.
- Perfil usa el `cortesModel`, los recursos `SUCS/` y las selecciones gráficas
  reales. Las cotas son las del documento; se aplica altura mínima para leer
  capas delgadas y se indica expresamente. Seleccionar una capa abre su editor;
  Muestras/Lab cambia al mismo estrato. Agregar, mover, borrar y validar límites
  usan las funciones existentes. Origen del material permanece separado de SUCS.
- Fotografías muestra las tres categorías reales en tarjetas: Zona de ejecución,
  Interior de calicata y Acopios. Conserva cámara, selección, eliminación,
  estampado y persistencia. Las miniaturas limitan su decodificación a 480 px.
- Revisión reúne los bloqueos del validador original y permite ir al campo o
  estrato afectado. Excel usa el exportador original y requiere visitar la
  revisión. No se agregaron reglas obligatorias ni se cambió la plantilla.
- El dock global conserva componente, dimensiones, área segura, animación,
  acciones y placeholder de voz. Una proyección en el editor ordena las mismas
  acciones y actualiza el icono de etapas. `Main.qml` sólo conecta esa proyección
  y el identificador de etapa al dock que ya existe.

No se modificaron backend, autenticación, Supabase, modelos C++, plantillas ni
datos locales. No se añadieron dependencias ni assets. Se eliminó una llamada
preexistente a `photoReveal`, objeto inexistente, al incorporar fotografías.

## Recursos y empaquetado

Se inventarió `C:/Users/PC-02/Documents/calicatas`. Se leyeron LICENSE y pubspec
de wizard_stepper (MIT), patterns_canvas (MIT) y dashboard (Apache-2.0).
Son proyectos Flutter: se usaron como referencia conceptual, sin copiar código,
assets ni dependencias. No se descargó contenido ni se descompiló Calicatas María.

Los dos componentes nuevos, `CalicataProfile.qml` y `CalicataReview.qml`, se
registran con la misma estrategia de los QML existentes en `MOBILE_QML_FILES`,
`resources.qrc` y `resources_mobile_raw.qrc`. No hay otro motor Flow ni otro dock.

## Validación ejecutada

Herramientas locales Qt **6.9.3**, sin CMake, Ninja, Gradle, Androiddeployqt ni ADB.
Se añadió temporalmente al PATH el bin de Qt y `C:/Qt/Tools/mingw1310_64/bin`
para resolver el runtime de las herramientas; no se cambió la configuración del proyecto.

1. `qmlcachegen --only-bytecode -o <TEMP>/<nombre>.qmlc <fuente>`: PASS para
   CalicataFormPage, CalicatasEditorPage, CalicataProfile, CalicataReview y Main.
2. `qmlformat --ignore-settings <fuente>` con salida en TEMP, sin reescribir
   archivos: PASS para las cuatro páginas del rediseño.
3. `qmllint <fuentes>`: ejecutado sobre las cuatro páginas. Conserva advertencias
   por `InGe`/objetos C++ registrados en ejecución, resolución de IDs del código
   preexistente y propiedades `var` usadas como callbacks. Los nuevos componentes
   usan `pragma ComponentBehavior: Bound`. No es una validación del enlace C++.
4. Comparación Node del validador anterior y actual: **2.502 casos PASS**, mismo
   primer bloqueo. Incluye ausencia de muestras opcionales, origen antrópico
   separado de SUCS e intervalos de muestras fuera del estrato.
5. Comparación textual de **13 funciones originales PASS**: serialización,
   persistencia, normalización, intervalos, captura GPS, solicitudes de fotografías
   y exportación Excel conservadas. IDs de campos originales conservados.
6. Pruebas de funciones de navegación: cinco etapas y accesos secundarios,
   selección de estrato/laboratorio y bloqueo al no poder confirmar un campo: PASS.
7. `git diff --check` focal: PASS. Recursos nuevos y patrones SUCS comprobados
   contra archivos y QRC físicos.

Durante el checkpoint, el mantenimiento automático de Git intentó un repack y
falló por memoria; el commit sí quedó creado y se verificó. Una ejecución posterior
de qmlcachegen también terminó por excepción nativa; la repetición aislada sobre
la fuente final pasó. No se ocultaron esos resultados ni se modificó la configuración
global de Git. El commit de implementación desactiva sólo el auto mantenimiento
para ese comando.

## Límites y QA pendiente

- `BLOCKED_BY_MISSING_RESOURCE`: exportación PDF de Calicatas (`exportPdfFlow`
  no existe); el callback histórico se conserva, pero sus opciones no se muestran.
- No hay operación existente de finalización persistida en el contrato examinado:
  la revisión concluye con Exportar Excel, sin inventar un estado de negocio.
- Las fotografías mantienen tres slots por categoría; no se inventaron fotos
  ilimitadas ni asociaciones nuevas por estrato.
- El mapa se abre con la infraestructura existente; no se incrusta otro proveedor.
- **Pendiente del usuario**: compilar Android arm64-v8a en Qt Creator, instalar,
  revisar logcat y probar en teléfono. No se afirma QA visual/físico completado.
- Regresión física necesaria: cambio de ficha y cuenta, borradores al salir,
  teclado y dock, GPS con permisos/cancelación, cámara/galería/cancelación,
  agregar/mover/borrar capas, muestras, logos y exportación XLSX real.

## Git

Fase A: `095e9a0`, checkpoint exacto del estado previo de seis archivos ya
modificados (formulario, editor, Main, CMake y dos QRC). Conserva los cambios
anteriores del usuario sin atribuirlos al rediseño ni alterar archivos de trabajo.
Fase B: commit de implementación con las diferencias de esta tarea y este informe.
Los demás cambios preexistentes del repositorio permanecen fuera de estos commits.
