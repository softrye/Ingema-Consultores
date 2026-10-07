# InGe+ / AppCalicatasDemo

Repositorio limpio preparado para continuar el desarrollo de **InGe+** en **Qt Creator / Qt 6 / QML / Android**.

Esta base fue generada desde `AppCalicatasDemo.zip` y está lista para subir a GitHub sin arrastrar builds, APKs, respaldos antiguos ni archivos temporales.

## Qué incluye

- Código C++/Qt y QML.
- Interfaz móvil QML.
- Login / registro con Supabase.
- Organizador de documentos.
- Mapa / GPS.
- Editor de calicatas.
- Exportación de calicatas a Excel.
- Conversión de ficha editable a Excel.
- QXlsx para manejo de Excel.
- Recursos UI reales de Fase 5.4.
- Recursos Android necesarios para empaquetado.
- Plantilla `Templates/Calicata_Formato.xlsx`.

## Estructura principal

```text
android/                         Configuración Android y recursos launcher
images/                          Imágenes usadas por resources.qrc
qml/Mobile/                      Interfaz móvil QML
resources/ui/                    Recursos UI Fase 5.4
Templates/                       Plantilla Excel de calicatas
thirdparty/QXlsx/                Librería C++ para Excel
scripts/                         Scripts Git + scripts técnicos usados por resources.qrc
CMakeLists.txt                   Configuración principal Qt/CMake
resources.qrc                    Recursos Qt generales
resources_mobile_raw.qrc         Fallback raw para QML móvil
```

## Qué se excluyó

- `build/`
- `.qtcreator/`
- APK/AAB
- RAR/ZIP internos
- scripts viejos de limpieza/log
- backups `.bak`
- QML de respaldo `backup/no_borrar`
- reportes y validaciones generadas
- Word/PDF

## Primer uso en Qt Creator

1. Abrir `CMakeLists.txt` desde Qt Creator.
2. Seleccionar kit Android o Desktop.
3. Ejecutar CMake Configure.
4. Revisar `docs/CHECKLIST_COMPILACION.md`.

## Subir a GitHub

1. Crear un repositorio vacío en GitHub, recomendado como **privado**.
2. Ejecutar `scripts/00_iniciar_git_local.bat`.
3. Ejecutar `scripts/01_conectar_y_subir_a_github.bat` y pegar la URL del repo.

## Seguridad

El archivo `appcontext.cpp` conserva configuración de Supabase del proyecto. Para repo público, mover esa configuración antes de subir. Ver `docs/SEGURIDAD_CONFIG.md`.

## Fix V38.6 — mapa y GPS

La V38.6 filtra lecturas de ubicación imprecisas, evita mostrar como GPS una posición de red de ±2000 m, reconstruye el pellizco sobre una sola instancia `Map` y reduce la carga de renderizado del mapa. Véase `docs/FIX_V38_6_GPS_PRECISION_PINCH.md`.
