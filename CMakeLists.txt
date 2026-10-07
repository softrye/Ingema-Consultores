cmake_minimum_required(VERSION 3.16)
project(AppCalicatasDemo VERSION 1.1.9 LANGUAGES CXX)

# ---------------------------------------------------------
# INGE+ ANDROID RELEASE â€” Qt 6.9.3 / arm64-v8a
# ---------------------------------------------------------
if(ANDROID)
    set(INGE_ANDROID_PACKAGE_NAME "com.ingema.ingeplus" CACHE STRING
        "Package Android; permite un ID aislado para validaciones sin reemplazar datos")

    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "Debug" CACHE STRING
            "Tipo de compilacion Android" FORCE)
    endif()

    set(ANDROID_ABI "arm64-v8a" CACHE STRING
        "ABI Android de InGe+" FORCE)
    set(QT_ANDROID_ABIS "arm64-v8a" CACHE STRING
        "ABI Android empaquetada por Qt" FORCE)
    set(QT_ANDROID_BUILD_ALL_ABIS OFF CACHE BOOL
        "Compilar solamente arm64-v8a" FORCE)

    # El codigo nativo mantiene compatibilidad desde Android 9 / API 28.
    set(ANDROID_PLATFORM "android-28" CACHE STRING
        "API nativa minima Android" FORCE)

    set(ANDROID_STL "c++_shared" CACHE STRING
        "STL Android" FORCE)
    set(CMAKE_ANDROID_STL_TYPE "c++_shared" CACHE STRING
        "STL usada por CMake" FORCE)

    set(QT_ANDROID_DEPLOYMENT_TYPE "${CMAKE_BUILD_TYPE}" CACHE STRING
        "Tipo de despliegue Android" FORCE)
endif()


# V38.10.4: raiz estable del codigo fuente. Evita que rutas relativas
# se interpreten contra la carpeta de build durante reconfiguraciones.
set(INGE_PROJECT_ROOT "${CMAKE_CURRENT_LIST_DIR}")

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ---------------------------------------------------------
# Switch: construir target Mobile tambiÃ©n en Windows (opcional)
# ---------------------------------------------------------
option(INGE_BUILD_MOBILE "Build shared QML application (Android and Desktop)" ON)
option(INGE_CORE_ENABLED "Enable InGe Core remote execution via the secure Supabase bus" OFF)
if(ANDROID OR IOS)
    set(INGE_BUILD_MOBILE ON CACHE BOOL "" FORCE)
endif()

# ----------------------------
# Qt base
# ----------------------------
find_package(QT NAMES Qt6 Qt5 REQUIRED
    COMPONENTS Core Network Positioning Location Quick Qml Xml Concurrent
)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED
    COMPONENTS Core Network Positioning Location Quick Qml Xml Concurrent
)

# Si vamos a compilar Mobile, necesitamos QuickControls2
if(INGE_BUILD_MOBILE)
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS QuickControls2 QuickDialogs2)
    if(QT_VERSION_MAJOR GREATER_EQUAL 6)
        find_package(Qt6 REQUIRED COMPONENTS QuickEffects)
        find_package(Qt6 REQUIRED COMPONENTS ShaderTools)
    endif()
endif()

# Qt 6.9 Android/QML policy defaults: evita warnings de desarrollo en build Android.
if(QT_VERSION_MAJOR GREATER_EQUAL 6)
    if(COMMAND qt_policy)
        qt_policy(SET QTP0002 NEW)
        qt_policy(SET QTP0004 NEW)
    endif()
endif()

# Desktop usa Widgets/QuickWidgets/Pdf (solo si NO es Android/iOS)
if(NOT ANDROID AND NOT IOS AND NOT INGE_BUILD_MOBILE)
    find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Widgets QuickWidgets Pdf PdfWidgets)
endif()

# ----------------------------
# DESKTOP (Widgets) - tu app actual (solo desktop real)
# ----------------------------
if(NOT ANDROID AND NOT IOS AND NOT INGE_BUILD_MOBILE)

    add_subdirectory(thirdparty/QXlsx)

    set(PROJECT_SOURCES
        main.cpp
        mainwindow.cpp mainwindow.h mainwindow.ui
        homewindow.cpp homewindow.h homewindow.ui
        calicatawindow.cpp calicatawindow.h calicatawindow.ui
        corterowwidget.cpp corterowwidget.h corterowwidget.ui
        gpsmanager.cpp gpsmanager.h
        mapcontroller.h
        perfilwindow.cpp perfilwindow.h perfilwindow.ui
        cardframe.cpp cardframe.h
        timestampdialog.cpp timestampdialog.h timestampdialog.ui
        ubicacionwindow.ui ubicacionwindow.cpp ubicacionwindow.h
        resources.qrc
        guardarcalicatadialog.h guardarcalicatadialog.cpp
        calicataseditorwindow.h calicataseditorwindow.cpp calicataseditorwindow.ui
        calicataexcelexporter.h calicataexcelexporter.cpp
        guardarexportdialog.h guardarexportdialog.cpp
        jsonwidgetserializer.h jsonwidgetserializer.cpp
        toggleswitch.h toggleswitch.cpp
        editablemeta.cpp editablemeta.h
        exportexcelbatchdialog.h exportexcelbatchdialog.cpp
        selectfolderdialog.h selectfolderdialog.cpp

        gps/demo.nmea
        NoWheelComboBox.h
        ResourcesImagePickerDialog.h
        excelpdfpreviewdialog.h excelpdfpreviewdialog.cpp
        appcontext.h appcontext.cpp
        supabaseclient.h supabaseclient.cpp
        authsession.h authsession.cpp
        clouddocs.h clouddocs.cpp
        supabasestorageclient.h supabasestorageclient.cpp
        settingshelper.h
        syncmanifest.h syncmanifest.cpp
        syncengine.h syncengine.cpp
        pathscope.h pathscope.cpp
        appicon.rc
        globalsearch.h globalsearch.cpp
    )

    if(${QT_VERSION_MAJOR} GREATER_EQUAL 6)
        qt_add_executable(AppCalicatasDemo
            WIN32
            MANUAL_FINALIZATION
            ${PROJECT_SOURCES}
            ingetheme.h ingetheme.cpp
            android/AndroidManifest.xml
            taludeseditorwindow.h taludeseditorwindow.cpp
            taludeseditorwindow.ui
            TaludSueloWindow.h TaludSueloWindow.cpp
            TaludRocaWindow.h TaludRocaWindow.cpp
            TaludRocaWindow.ui
            TaludSueloWindow.ui
            taludformbase.h taludformbase.cpp
            verticallabel.h verticallabel.cpp
            calicatamapdialog.h calicatamapdialog.cpp
            paintcanvaswidget.h paintcanvaswidget.cpp
            taludpaintdialog.h taludpaintdialog.cpp


        )
    else()
        add_executable(AppCalicatasDemo ${PROJECT_SOURCES})
    endif()

    target_include_directories(AppCalicatasDemo PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/QXlsx/header
    )

    target_link_libraries(AppCalicatasDemo PRIVATE
        Qt${QT_VERSION_MAJOR}::Widgets
        Qt${QT_VERSION_MAJOR}::Positioning
        Qt${QT_VERSION_MAJOR}::Location
        Qt${QT_VERSION_MAJOR}::Quick
        Qt${QT_VERSION_MAJOR}::Qml
        Qt${QT_VERSION_MAJOR}::QuickWidgets
        Qt${QT_VERSION_MAJOR}::Xml
        Qt${QT_VERSION_MAJOR}::Pdf
        Qt${QT_VERSION_MAJOR}::PdfWidgets
        Qt${QT_VERSION_MAJOR}::Concurrent
        Qt${QT_VERSION_MAJOR}::Network
        Qt${QT_VERSION_MAJOR}::Core
    )

    if(TARGET QXlsx::QXlsx)
        target_link_libraries(AppCalicatasDemo PRIVATE QXlsx::QXlsx)
    elseif(TARGET QXlsx)
        target_link_libraries(AppCalicatasDemo PRIVATE QXlsx)
    else()
        message(FATAL_ERROR "No se encontrÃ³ el target de QXlsx. Revisa thirdparty/QXlsx/CMakeLists.txt")
    endif()

    if(WIN32)
        find_package(Qt${QT_VERSION_MAJOR} QUIET COMPONENTS AxContainer)
        if(TARGET Qt${QT_VERSION_MAJOR}::AxContainer)
            target_link_libraries(AppCalicatasDemo PRIVATE Qt${QT_VERSION_MAJOR}::AxContainer)
            target_compile_definitions(AppCalicatasDemo PRIVATE APP_HAS_ACTIVEX=1)
        endif()
    endif()

    if(${QT_VERSION_MAJOR} GREATER_EQUAL 6)
        qt_finalize_executable(AppCalicatasDemo)
    endif()

endif() # DESKTOP


# ----------------------------
# MOBILE (QML) - target separado
# ----------------------------

if(INGE_BUILD_MOBILE)

    # Android/Mobile necesita QXlsx para exportar fichas Excel.
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/QXlsx/CMakeLists.txt")
        add_subdirectory(thirdparty/QXlsx)
    endif()

    # Cartography is provided by InGe Earth/Cesium; no native map provider dependency.

    set(MOBILE_SOURCES
        "${INGE_PROJECT_ROOT}/main_mobile.cpp"
        "${INGE_PROJECT_ROOT}/src/core/InGeCore.h"
        "${INGE_PROJECT_ROOT}/src/core/InGeCore.cpp"
        "${INGE_PROJECT_ROOT}/src/core/RemoteExecutor.cpp"
        "${INGE_PROJECT_ROOT}/src/core/RemoteExecutor.h"
        "${INGE_PROJECT_ROOT}/src/core/GeminiAssistant.cpp"
        "${INGE_PROJECT_ROOT}/src/core/GeminiAssistant.h"
        "${INGE_PROJECT_ROOT}/src/core/InGeCoreContext.h"
        "${INGE_PROJECT_ROOT}/src/core/InGeCoreTypes.h"
        "${INGE_PROJECT_ROOT}/src/core/InGeCoreSkill.h"
        "${INGE_PROJECT_ROOT}/resources.qrc"

        # AUTH compartido con Desktop
        "${INGE_PROJECT_ROOT}/appcontext.h"
        "${INGE_PROJECT_ROOT}/appcontext.cpp"
        "${INGE_PROJECT_ROOT}/settingshelper.h"
        "${INGE_PROJECT_ROOT}/supabaseclient.h"
        "${INGE_PROJECT_ROOT}/supabaseclient.cpp"
        "${INGE_PROJECT_ROOT}/authsession.h"
        "${INGE_PROJECT_ROOT}/authsession.cpp"
        "${INGE_PROJECT_ROOT}/clouddocs.h"
        "${INGE_PROJECT_ROOT}/clouddocs.cpp"
        "${INGE_PROJECT_ROOT}/src/documents/nothingdocuments.h"
        "${INGE_PROJECT_ROOT}/src/documents/nothingdocuments.cpp"
        "${INGE_PROJECT_ROOT}/src/documents/nothingfileops.h"
        "${INGE_PROJECT_ROOT}/src/documents/nothingfileops.cpp"
        "${INGE_PROJECT_ROOT}/betadiagnostics.h"
        "${INGE_PROJECT_ROOT}/betadiagnostics.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionrepository.h"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionrepository.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionlocalstore.h"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionlocalstore.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionsynccontroller.h"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionsynccontroller.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionflutterbridge.h"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionflutterbridge.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionsnapshotexporter.h"
        "${INGE_PROJECT_ROOT}/src/cpp/renditionsnapshotexporter.cpp"
        "${INGE_PROJECT_ROOT}/androidcalicataexporter.h"
        "${INGE_PROJECT_ROOT}/androidcalicataexporter.cpp"
        "${INGE_PROJECT_ROOT}/src/cpp/googledriveexporttransport.h"
        "${INGE_PROJECT_ROOT}/src/cpp/googledriveexporttransport.cpp"
        "${INGE_PROJECT_ROOT}/calicatasyncpolicy.h"
        "${INGE_PROJECT_ROOT}/calicatacloudservice.h"
        "${INGE_PROJECT_ROOT}/calicatacloudservice.cpp"
        "${INGE_PROJECT_ROOT}/dropboxbridge.h"
        "${INGE_PROJECT_ROOT}/dropboxbridge.cpp"
        "${INGE_PROJECT_ROOT}/firstexperiencecontroller.h"
        "${INGE_PROJECT_ROOT}/firstexperiencecontroller.cpp"
        "${INGE_PROJECT_ROOT}/ingenarrator.h"
        "${INGE_PROJECT_ROOT}/ingenarrator.cpp"
        "${INGE_PROJECT_ROOT}/ingeexperienceaudio.h"
        "${INGE_PROJECT_ROOT}/ingeexperienceaudio.cpp"
        "${INGE_PROJECT_ROOT}/flowhaptics.h"
        "${INGE_PROJECT_ROOT}/flowhaptics.cpp"
        "${INGE_PROJECT_ROOT}/mapworkspacecontroller.h"
        "${INGE_PROJECT_ROOT}/mapworkspacecontroller.cpp"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeGraphicsCore.h"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeGraphicsCore.cpp"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeGraphicsDiagnostics.h"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeGraphicsDiagnostics.cpp"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeEarthHostController.h"
        "${INGE_PROJECT_ROOT}/src/graphics/InGeEarthHostController.cpp"
        "${INGE_PROJECT_ROOT}/src/dock/DockContextController.h"
        "${INGE_PROJECT_ROOT}/src/dock/DockContextController.cpp"
        "${INGE_PROJECT_ROOT}/src/dock/DockCommandRouter.h"
        "${INGE_PROJECT_ROOT}/src/dock/DockCommandRouter.cpp"
    )

    # Falla temprano y con ruta de SOURCE clara, antes de qt_add_executable.
    foreach(_inge_mobile_source IN LISTS MOBILE_SOURCES)
        if(NOT EXISTS "${_inge_mobile_source}")
            message(FATAL_ERROR "Archivo C++/recurso requerido ausente: ${_inge_mobile_source}")
        endif()
    endforeach()


    set(_MOBILE_WIN32 "")
    if(WIN32)
        set(_MOBILE_WIN32 WIN32)
    endif()

    if(${QT_VERSION_MAJOR} GREATER_EQUAL 6)

        # V38.17 MOC BEGIN: PRETARGET
        # PermissionHelper se excluye COMPLETAMENTE de AUTOMOC antes de crear
        # el target. Es necesario excluir tanto el .h como el .cpp, porque
        # AUTOMOC inspecciona el source y busca automaticamente su header gemelo.
        set_source_files_properties(
            "${INGE_PROJECT_ROOT}/permissionhelper.h"
            "${INGE_PROJECT_ROOT}/permissionhelper.cpp"
            PROPERTIES
                SKIP_AUTOMOC ON
                SKIP_AUTOGEN ON
        )
        # V38.17 MOC END: PRETARGET
        qt_add_executable(AppCalicatasMobile
            ${_MOBILE_WIN32}
            MANUAL_FINALIZATION
            ${MOBILE_SOURCES}
            "${INGE_PROJECT_ROOT}/permissionhelper.cpp"
            "${INGE_PROJECT_ROOT}/docsops.h"
            "${INGE_PROJECT_ROOT}/docsops.cpp"
            "${INGE_PROJECT_ROOT}/docscontroller.h"
            "${INGE_PROJECT_ROOT}/docscontroller.cpp"
        )
        if(WIN32)
            set_target_properties(AppCalicatasMobile PROPERTIES OUTPUT_NAME AppCalicatasDemo)
            if(MINGW)
                set_source_files_properties(
                    "${CMAKE_CURRENT_BINARY_DIR}/.rcc/qmlcache/AppCalicatasMobile_qml/Mobile/Main_qml.cpp"
                    "${CMAKE_CURRENT_BINARY_DIR}/.rcc/qmlcache/AppCalicatasMobile_qml/Mobile/pages/CalicataFormPage_qml.cpp"
                    PROPERTIES COMPILE_OPTIONS "-Wa,-mbig-obj")
            endif()
        endif()
        # V38.17 MOC BEGIN: POSTTARGET
        # MOC manual y determinista. Esta firma genera una fuente independiente
        # y evita que moc_permissionhelper.cpp vuelva a incluirse desde
        # AppCalicatasMobile_autogen/mocs_compilation.cpp.
        qt6_wrap_cpp(INGE_PERMISSIONHELPER_MOC_SOURCES
            "${INGE_PROJECT_ROOT}/permissionhelper.h"
            TARGET AppCalicatasMobile
        )
        target_sources(AppCalicatasMobile PRIVATE
            ${INGE_PERMISSIONHELPER_MOC_SOURCES}
        )
        set_property(TARGET AppCalicatasMobile PROPERTY AUTOGEN_PARALLEL 1)
        message(STATUS "InGe+ V38.17 MOC PermissionHelper manual habilitado")
        # V38.17 MOC END: POSTTARGET

        if(ANDROID)
            # El Home se entrega dentro del AAR Flutter. Evita instalar una
            # mezcla donde QML/Java sean nuevos pero Flutter siga mostrando la
            # interfaz anterior (sin Rendiciones).
            set(INGE_FLUTTER_MODULE_DIR
                "${CMAKE_CURRENT_SOURCE_DIR}/flutter/inge_earth")
            file(GLOB_RECURSE INGE_FLUTTER_RUNTIME_SOURCES CONFIGURE_DEPENDS
                "${INGE_FLUTTER_MODULE_DIR}/lib/*.dart"
                "${INGE_FLUTTER_MODULE_DIR}/assets/*")
            list(APPEND INGE_FLUTTER_RUNTIME_SOURCES
                "${INGE_FLUTTER_MODULE_DIR}/pubspec.yaml"
                "${INGE_FLUTTER_MODULE_DIR}/pubspec.lock")
            set(INGE_FLUTTER_RELEASE_AAR
                "${INGE_FLUTTER_MODULE_DIR}/build/host/outputs/repo/com/ingema/inge_earth/flutter_release/1.0/flutter_release-1.0.aar")
            file(GLOB INGE_FLUTTER_SDK_HINTS
                "$ENV{USERPROFILE}/Develop/flutter-*/flutter/bin")
            # Descarta valores heredados del cache que solo contienen
            # "flutter" y no son ejecutables resolubles por Qt Creator.
            if(INGE_FLUTTER_EXECUTABLE AND
               NOT EXISTS "${INGE_FLUTTER_EXECUTABLE}")
                unset(INGE_FLUTTER_EXECUTABLE CACHE)
                unset(INGE_FLUTTER_EXECUTABLE)
            endif()
            find_program(INGE_FLUTTER_EXECUTABLE
                NAMES flutter.bat flutter
                HINTS "$ENV{FLUTTER_ROOT}/bin" ${INGE_FLUTTER_SDK_HINTS}
                DOC "Flutter executable used to rebuild the shared add-to-app AAR")
            if(NOT INGE_FLUTTER_EXECUTABLE)
                message(FATAL_ERROR "No se encontrÃ³ Flutter SDK para generar el AAR compartido.")
            endif()
            add_custom_command(
                OUTPUT "${INGE_FLUTTER_RELEASE_AAR}"
                COMMAND "${INGE_FLUTTER_EXECUTABLE}" pub get
                COMMAND "${CMAKE_COMMAND}"
                    "-DINGE_FLUTTER_ANDROID_DIR=${INGE_FLUTTER_MODULE_DIR}/.android"
                    -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/IngePrepareFlutterAndroid.cmake"
                COMMAND "${INGE_FLUTTER_EXECUTABLE}" build aar --release --no-pub
                WORKING_DIRECTORY "${INGE_FLUTTER_MODULE_DIR}"
                DEPENDS
                    ${INGE_FLUTTER_RUNTIME_SOURCES}
                    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/IngePrepareFlutterAndroid.cmake"
                COMMENT "Actualizando AAR Flutter compartido cuando sus fuentes cambian"
                VERBATIM
                USES_TERMINAL)
            add_custom_target(inge_flutter_aar DEPENDS "${INGE_FLUTTER_RELEASE_AAR}")
            add_dependencies(AppCalicatasMobile inge_flutter_aar)

            # Actual Gemini Live React sources; generated only when the user builds.
            find_program(INGE_NPM_EXECUTABLE NAMES npm.cmd npm REQUIRED)
            find_program(INGE_NODE_EXECUTABLE NAMES node.exe node REQUIRED)
            file(GLOB_RECURSE INGE_AI_WEB_SOURCES CONFIGURE_DEPENDS
                "${CMAKE_CURRENT_SOURCE_DIR}/android/web/inge-ai/src/*")
            set(INGE_AI_WEB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android/web/inge-ai")
            add_custom_command(
                OUTPUT "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/inge-ai/index.html"
                COMMAND "${INGE_NODE_EXECUTABLE}" "${INGE_AI_WEB_DIR}/prepare-dependencies.mjs"
                    --npm "${INGE_NPM_EXECUTABLE}"
                COMMAND "${INGE_NPM_EXECUTABLE}" run build
                WORKING_DIRECTORY "${INGE_AI_WEB_DIR}"
                DEPENDS ${INGE_AI_WEB_SOURCES}
                    "${INGE_AI_WEB_DIR}/package.json" "${INGE_AI_WEB_DIR}/package-lock.json"
                    "${INGE_AI_WEB_DIR}/prepare-dependencies.mjs"
                    "${INGE_AI_WEB_DIR}/index.html" "${INGE_AI_WEB_DIR}/vite.config.ts"
                    "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/cesium/ui/inge-earth-ui.css"
                COMMENT "Generando Gemini Live Web Console para el paquete Android"
                VERBATIM USES_TERMINAL)
            add_custom_target(inge_ai_web_assets
                DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/android/assets/inge-ai/index.html")
            add_dependencies(AppCalicatasMobile inge_ai_web_assets)

            # ConfiguraciÃ³n Android para empaquetar APK/AAB con Qt 6.9.x
            set_property(TARGET AppCalicatasMobile PROPERTY
                QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android"
            )
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_ABIS "arm64-v8a")
            set_property(TARGET AppCalicatasMobile PROPERTY
                QT_ANDROID_PACKAGE_NAME "${INGE_ANDROID_PACKAGE_NAME}")
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_VERSION_CODE 122)
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_VERSION_NAME "1.1.13-native-location")
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_MIN_SDK_VERSION 28)
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_TARGET_SDK_VERSION 35)
            # Flutter 3.44.x plugins publish their AAR metadata against API 37.
            # compileSdk does not change the app's targetSdk/runtime behavior.
            set_property(TARGET AppCalicatasMobile PROPERTY QT_ANDROID_COMPILE_SDK_VERSION 37.0)

            # Declaraciones explÃ­citas requeridas por QLocationPermission.
            # Qt 6.9 las inserta en el manifiesto Android generado.
            if(COMMAND qt_add_android_permission)
                qt_add_android_permission(AppCalicatasMobile
                    NAME android.permission.ACCESS_COARSE_LOCATION)
                qt_add_android_permission(AppCalicatasMobile
                    NAME android.permission.ACCESS_FINE_LOCATION)
            endif()
        endif()


        # ---------------------------------------------------------
        # ANDROID RESOURCE FIX V53:
        # No generar android/res/drawable/ic_launcher.xml.
        # Android/Gradle falla si existen a la vez:
        #   drawable/ic_launcher.png
        #   drawable/ic_launcher.xml
        # Este bloque elimina el XML viejo y deja solo el PNG.
        # ---------------------------------------------------------
        if(ANDROID)
            set(_INGE_ANDROID_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android")
            set(_INGE_ANDROID_MANIFEST "${_INGE_ANDROID_DIR}/AndroidManifest.xml")
            set(_INGE_ANDROID_DRAWABLE_DIR "${_INGE_ANDROID_DIR}/res/drawable")
            file(MAKE_DIRECTORY "${_INGE_ANDROID_DRAWABLE_DIR}")

            # Limpieza del recurso duplicado en la carpeta fuente.
            file(REMOVE "${_INGE_ANDROID_DRAWABLE_DIR}/ic_launcher.xml")
            file(REMOVE "${_INGE_ANDROID_DRAWABLE_DIR}/ic_launcher_round.xml")

            # Limpieza del recurso duplicado que pudo quedar en la carpeta de build.
            file(REMOVE "${CMAKE_CURRENT_BINARY_DIR}/android-build-AppCalicatasMobile/res/drawable/ic_launcher.xml")
            file(REMOVE "${CMAKE_CURRENT_BINARY_DIR}/android-build-AppCalicatasMobile/res/drawable/ic_launcher_round.xml")

            if(EXISTS "${_INGE_ANDROID_MANIFEST}")
                file(READ "${_INGE_ANDROID_MANIFEST}" _INGE_MANIFEST_TEXT)
                string(REPLACE "android:icon=\"@mipmap/ic_launcher\""
                               "android:icon=\"@drawable/ic_launcher\""
                               _INGE_MANIFEST_TEXT "${_INGE_MANIFEST_TEXT}")
                string(REPLACE "android:roundIcon=\"@mipmap/ic_launcher_round\""
                               "android:roundIcon=\"@drawable/ic_launcher\""
                               _INGE_MANIFEST_TEXT "${_INGE_MANIFEST_TEXT}")
                file(WRITE "${_INGE_ANDROID_MANIFEST}" "${_INGE_MANIFEST_TEXT}")
            else()
                message(WARNING "No se encontro android/AndroidManifest.xml para aplicar icon fix V53.")
            endif()
        endif()


        # ---------------------------------------------------------
        # V54: build limpio en Android/Clang.
        # Quita warning nodiscard de QtConcurrent::run heredado de docsops/docscontroller.
        # ---------------------------------------------------------
        if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
            target_compile_options(AppCalicatasMobile PRIVATE
                -Wno-unused-result
            )
        endif()

        target_include_directories(AppCalicatasMobile PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
        )

        target_link_libraries(AppCalicatasMobile PRIVATE
            Qt${QT_VERSION_MAJOR}::Core
            Qt${QT_VERSION_MAJOR}::Gui
            Qt${QT_VERSION_MAJOR}::Network
            Qt${QT_VERSION_MAJOR}::Qml
            Qt${QT_VERSION_MAJOR}::Quick
            Qt${QT_VERSION_MAJOR}::QuickControls2
            Qt${QT_VERSION_MAJOR}::QuickDialogs2
            Qt${QT_VERSION_MAJOR}::Location
            Qt${QT_VERSION_MAJOR}::Positioning
            Qt${QT_VERSION_MAJOR}::Concurrent
            Qt${QT_VERSION_MAJOR}::Xml
        )

        if(QT_VERSION_MAJOR GREATER_EQUAL 6)
            target_include_directories(AppCalicatasMobile PRIVATE "${INGE_PROJECT_ROOT}/src/documents")
            target_link_libraries(AppCalicatasMobile PRIVATE Qt6::QuickEffects Qt6::GuiPrivate)
        endif()

        if(ANDROID)
            target_link_libraries(AppCalicatasMobile PRIVATE vulkan)
        endif()

        set_property(TARGET AppCalicatasMobile PROPERTY CXX_STANDARD 20)
        set_property(TARGET AppCalicatasMobile PROPERTY CXX_STANDARD_REQUIRED ON)

        if(TARGET QXlsx::QXlsx)
            target_link_libraries(AppCalicatasMobile PRIVATE QXlsx::QXlsx)
            target_compile_definitions(AppCalicatasMobile PRIVATE INGE_HAS_QXLSX=1)
        elseif(TARGET QXlsx)
            target_link_libraries(AppCalicatasMobile PRIVATE QXlsx)
            target_compile_definitions(AppCalicatasMobile PRIVATE INGE_HAS_QXLSX=1)
        else()
            message(WARNING "No se encontrÃ³ QXlsx para Mobile. ExportaciÃ³n Excel podrÃ­a no compilar.")
        endif()


        # appcontext conserva su configuracion heredada. PermissionHelper
        # usa Q_OBJECT/Q_INVOKABLE y debe pasar por AUTOMOC.
        set_source_files_properties(
            appcontext.h
            PROPERTIES SKIP_AUTOMOC ON
        )

        target_compile_definitions(AppCalicatasMobile PRIVATE INGE_MOBILE=1)
        target_compile_definitions(AppCalicatasMobile PRIVATE
            INGE_CORE_ENABLED=$<BOOL:${INGE_CORE_ENABLED}>)

        # âœ… Recomendado: asegura que los plugins QML (Location/Positioning, etc.) se incluyan al desplegar

        # V53: main_mobile.cpp carga Main.qml con fallback qrc directo si loadFromModule falla.
        # ============================
        # QML precompilado (qmlcachegen)
        # ============================
        set(MOBILE_QML_DIR "${CMAKE_CURRENT_SOURCE_DIR}/qml/Mobile")

        set(MOBILE_QML_FILES
            "${MOBILE_QML_DIR}/Main.qml"
            "${MOBILE_QML_DIR}/documents/NothingDocumentsRoot.qml"
            "${MOBILE_QML_DIR}/documents/NothingIcon.qml"
            "${MOBILE_QML_DIR}/documents/NothingButton.qml"
            "${MOBILE_QML_DIR}/documents/NothingEntry.qml"
            "${MOBILE_QML_DIR}/AppShell.qml"
            "${MOBILE_QML_DIR}/HeaderBar.qml"
            "${MOBILE_QML_DIR}/BottomNav.qml"
            "${MOBILE_QML_DIR}/GlobalSearchOverlay.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowColors.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowTypography.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowSpacing.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowRadius.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowElevation.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowMetrics.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowOpacity.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowDuration.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowEasing.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowSpring.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowTheme.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowVariant.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowState.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowMotion.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowGesture.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowAccessibility.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowPerformance.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowRipple.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowBusyIndicator.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowThreeBalls.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowProgressRing.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowFocusRing.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowGlassSurface.qml"
            "${MOBILE_QML_DIR}/flowcore/LiquidGlassSurface.qml"
            "${MOBILE_QML_DIR}/flowcore/GlobalContextDock.qml"
            "${MOBILE_QML_DIR}/flowcore/ContextPublisher.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowSurface.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowText.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowButton.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowCard.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowField.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowTab.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowToolbar.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowSection.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowPage.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowSheet.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowDialog.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowGlassButton.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowGlassCard.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowDeepPressArea.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowQuickBubble.qml"
            "${MOBILE_QML_DIR}/flowcore/ImeAwareFlickable.qml"
            "${MOBILE_QML_DIR}/onboarding/FirstExperience.qml"
            "${MOBILE_QML_DIR}/onboarding/ExperienceScene.qml"
            "${MOBILE_QML_DIR}/onboarding/AnimatedGreeting.qml"
            "${MOBILE_QML_DIR}/onboarding/MorphingPlus.qml"
            "${MOBILE_QML_DIR}/onboarding/ExperienceCard.qml"
            "${MOBILE_QML_DIR}/onboarding/OnboardingProgress.qml"
            "${MOBILE_QML_DIR}/onboarding/PremiumBackdrop.qml"
            "${MOBILE_QML_DIR}/onboarding/SceneTitle.qml"
            "${MOBILE_QML_DIR}/onboarding/HeroIllustration.qml"
            "${MOBILE_QML_DIR}/onboarding/PremiumGlassCard.qml"
            "${MOBILE_QML_DIR}/onboarding/NarrationWave.qml"
            "${MOBILE_QML_DIR}/onboarding/PhoneDemoFrame.qml"
            "${MOBILE_QML_DIR}/onboarding/BrandFooter.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/WelcomeScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/CommitmentScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/LanguageScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/PersonalizationScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/MotionLabScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/HomeTourScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/CreateTourScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/MapTourScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/OfflineScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/DocumentsScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/PrivacyScene.qml"
            "${MOBILE_QML_DIR}/onboarding/scenes/ReadyScene.qml"
            "${MOBILE_QML_DIR}/components/AppButton.qml"
            "${MOBILE_QML_DIR}/components/AppCard.qml"
            "${MOBILE_QML_DIR}/components/AppLoadingOverlay.qml"
            "${MOBILE_QML_DIR}/components/AppModuleCard.qml"
            "${MOBILE_QML_DIR}/components/AppPhotoSlot.qml"
            "${MOBILE_QML_DIR}/components/AppStatusChip.qml"
            "${MOBILE_QML_DIR}/components/CircularAvatar.qml"
            "${MOBILE_QML_DIR}/components/FlowIcon.qml"
            "${MOBILE_QML_DIR}/components/FlowIconButton.qml"
            "${MOBILE_QML_DIR}/components/BotonFlotante.qml"
            "${MOBILE_QML_DIR}/components/ModuloCard.qml"
            "${MOBILE_QML_DIR}/lib/GpsBus.js"
            "${MOBILE_QML_DIR}/lib/CalicataRules.js"
            "${MOBILE_QML_DIR}/lib/CalicataExcelImport.js"
            "${MOBILE_QML_DIR}/lib/CalicataElevation.js"
            "${MOBILE_QML_DIR}/lib/IconCatalog.js"
            "${MOBILE_QML_DIR}/lib/PropACalicataIconMap.js"
            "${MOBILE_QML_DIR}/lib/UiV2Resources.js"
            "${MOBILE_QML_DIR}/lib/UiV2Theme.js"
            "${MOBILE_QML_DIR}/pages/HomePage.qml"
            "${MOBILE_QML_DIR}/pages/HomePageContent.qml"
            "${MOBILE_QML_DIR}/pages/HomePagePhase1.qml"
            "${MOBILE_QML_DIR}/pages/LoginPage.qml"
            "${MOBILE_QML_DIR}/pages/LoginPageForm.qml"
            "${MOBILE_QML_DIR}/pages/MapPage.qml"
            "${MOBILE_QML_DIR}/pages/MapPageContent.qml"
            "${MOBILE_QML_DIR}/pages/MapWorkspacePage.qml"
            "${MOBILE_QML_DIR}/pages/MapNativePage.qml"
            "${MOBILE_QML_DIR}/pages/ProfilePage.qml"
            "${MOBILE_QML_DIR}/pages/ProfilePageContent.qml"
            "${MOBILE_QML_DIR}/pages/RegisterPage.qml"
            "${MOBILE_QML_DIR}/pages/RegisterPageForm.qml"
            "${MOBILE_QML_DIR}/pages/CalicatasEditorPage.qml"
            "${MOBILE_QML_DIR}/pages/CalicataFormPage.qml"
            "${MOBILE_QML_DIR}/pages/CalicataReview.qml"
            "${MOBILE_QML_DIR}/pages/CalicataLiquidGlass.qml"
            "${MOBILE_QML_DIR}/pages/CalicataProfile.qml"
            "${MOBILE_QML_DIR}/pages/CalicataPointPicker.qml"
            "${MOBILE_QML_DIR}/pages/CalicataPhotoEditor.qml"
            "${MOBILE_QML_DIR}/pages/CalicataOperationOverlay.qml"
            "${MOBILE_QML_DIR}/pages/Phase54CalicataOverview.qml"
            "${MOBILE_QML_DIR}/CalicataSaveOpenDialog.qml"
        )

        # Recursos del mÃ³dulo QML.
        # IMPORTANTE:
        # CalicataFormPage.qml carga:
        #     qrc:/InGe/Mobile/images/camera_thin_dark.svg
        # Por eso el recurso debe quedar con alias:
        #     images/camera_thin_dark.svg
        # dentro del mÃ³dulo URI InGe.Mobile.
        set(COREFLOW_SINGLETON_RESOURCES
            "${MOBILE_QML_DIR}/flowcore/InGeCoreFlow.qml"
            "${MOBILE_QML_DIR}/flowcore/FlowIcons.qml"
            "${MOBILE_QML_DIR}/flowcore/InGeIconLibrary.qml"
        )

        set(MOBILE_QML_RESOURCES)
        foreach(_coreflow_singleton IN LISTS COREFLOW_SINGLETON_RESOURCES)
            file(RELATIVE_PATH _coreflow_alias
                "${MOBILE_QML_DIR}" "${_coreflow_singleton}")
            set_source_files_properties("${_coreflow_singleton}" PROPERTIES
                QT_RESOURCE_ALIAS "${_coreflow_alias}"
            )
            list(APPEND MOBILE_QML_RESOURCES "${_coreflow_singleton}")
        endforeach()

        # Recursos usados por Main.qml: icons/*.png, fondos, logos, SVG, etc.
        # Sin esto, Android puede compilar pero la interfaz queda sin imÃ¡genes/fondos.
        file(GLOB_RECURSE MOBILE_EXTRA_RESOURCES CONFIGURE_DEPENDS
            "${MOBILE_QML_DIR}/icons/*"
            "${MOBILE_QML_DIR}/images/*"
            "${MOBILE_QML_DIR}/onboarding/assets/*"
            "${MOBILE_QML_DIR}/documents/assets/*"
        )
        foreach(_res IN LISTS MOBILE_EXTRA_RESOURCES)
            if(NOT IS_DIRECTORY "${_res}")
                file(RELATIVE_PATH _res_alias "${MOBILE_QML_DIR}" "${_res}")
                set_source_files_properties("${_res}" PROPERTIES QT_RESOURCE_ALIAS "${_res_alias}")
                list(APPEND MOBILE_QML_RESOURCES "${_res}")
            endif()
        endforeach()

        set(MOBILE_CAMERA_ICON "")
        set(MOBILE_CAMERA_ICON_CANDIDATES
            "${MOBILE_QML_DIR}/images/camera_thin_dark.svg"
            "${MOBILE_QML_DIR}/icons/camera_thin_dark.svg"
            "${CMAKE_CURRENT_SOURCE_DIR}/images/camera_thin_dark.svg"
            "${CMAKE_CURRENT_SOURCE_DIR}/icons/images/camera_thin_dark.svg"
            "${MOBILE_QML_DIR}/images/camera.svg"
            "${CMAKE_CURRENT_SOURCE_DIR}/icons/images/camera.svg"
        )

        foreach(_camera_candidate IN LISTS MOBILE_CAMERA_ICON_CANDIDATES)
            if(EXISTS "${_camera_candidate}")
                set(MOBILE_CAMERA_ICON "${_camera_candidate}")
                break()
            endif()
        endforeach()

        if(MOBILE_CAMERA_ICON)
            list(APPEND MOBILE_QML_RESOURCES "${MOBILE_CAMERA_ICON}")

            # Fuerza exactamente esta ruta:
            # qrc:/InGe/Mobile/images/camera_thin_dark.svg
            set_source_files_properties("${MOBILE_CAMERA_ICON}" PROPERTIES
                QT_RESOURCE_ALIAS "images/camera_thin_dark.svg"
            )
        else()
            message(WARNING
                "No se encontro camera_thin_dark.svg ni camera.svg. "
                "Copia el icono a qml/Mobile/images/camera_thin_dark.svg "
                "o corrige root.icCamera en CalicataFormPage.qml."
            )
        endif()

        # Alias para QML: Main.qml, pages/CalicataFormPage.qml, lib/GpsBus.js, etc.
        foreach(f IN LISTS MOBILE_QML_FILES)
            file(RELATIVE_PATH rel "${MOBILE_QML_DIR}" "${f}")
            set_source_files_properties("${f}" PROPERTIES QT_RESOURCE_ALIAS "${rel}")
        endforeach()

        # INGE_CPP_QMLDIR_FIX_V5_BEGIN
        # El URI InGe se registra desde main_mobile.cpp mediante
        # qmlRegisterSingletonInstance(). Las herramientas de Qt necesitan
        # un qmldir fisico para resolver "import InGe 1.0" durante CMake.
        set(_INGE_CPP_QML_ROOT "${CMAKE_CURRENT_BINARY_DIR}/InGe")
        set(_INGE_CPP_QMLDIR "${_INGE_CPP_QML_ROOT}/qmldir")
        set(_INGE_CPP_QMLDIR_TEXT "module InGe\n")

        file(MAKE_DIRECTORY "${_INGE_CPP_QML_ROOT}")

        set(_INGE_CPP_QMLDIR_CURRENT "")
        if(EXISTS "${_INGE_CPP_QMLDIR}")
            file(READ "${_INGE_CPP_QMLDIR}" _INGE_CPP_QMLDIR_CURRENT)
        endif()

        if(NOT "${_INGE_CPP_QMLDIR_CURRENT}" STREQUAL "${_INGE_CPP_QMLDIR_TEXT}")
            file(WRITE "${_INGE_CPP_QMLDIR}" "${_INGE_CPP_QMLDIR_TEXT}")
        endif()

        list(APPEND QML_IMPORT_PATH "${CMAKE_CURRENT_BINARY_DIR}")
        list(REMOVE_DUPLICATES QML_IMPORT_PATH)

        set_property(TARGET AppCalicatasMobile APPEND PROPERTY
            QT_QML_IMPORT_PATH "${CMAKE_CURRENT_BINARY_DIR}")
        # INGE_CPP_QMLDIR_FIX_V5_END

        # InGe.CoreFlow 3.0 se registra en main_mobile.cpp desde sus fuentes QML.
        # Esta copia de herramientas describe el mismo modulo para qmlcachegen
        # y qmlimportscanner; no crea otra instancia ni se empaqueta en el APK.
        set(_COREFLOW_QML_TOOL_ROOT
            "${CMAKE_CURRENT_BINARY_DIR}/InGe/CoreFlow")
        file(MAKE_DIRECTORY "${_COREFLOW_QML_TOOL_ROOT}")

        set(_COREFLOW_QML_TOOL_TYPES
            InGeCoreFlow
            FlowIcons
            InGeIconLibrary
            FlowColors
            FlowTypography
            FlowSpacing
            FlowRadius
            FlowElevation
            FlowMetrics
            FlowOpacity
            FlowDuration
            FlowEasing
            FlowSpring
            FlowTheme
            FlowVariant
            FlowState
            FlowAccessibility
            FlowPerformance
            FlowMotion
        )

        foreach(_coreflow_tool_type IN LISTS _COREFLOW_QML_TOOL_TYPES)
            configure_file(
                "${MOBILE_QML_DIR}/flowcore/${_coreflow_tool_type}.qml"
                "${_COREFLOW_QML_TOOL_ROOT}/${_coreflow_tool_type}.qml"
                COPYONLY
            )
        endforeach()

        file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/InGe/lib")
        configure_file(
            "${MOBILE_QML_DIR}/lib/IconCatalog.js"
            "${CMAKE_CURRENT_BINARY_DIR}/InGe/lib/IconCatalog.js"
            COPYONLY
        )

        string(CONCAT _COREFLOW_QMLDIR_TEXT
            "module InGe.CoreFlow\n"
            "singleton InGeCoreFlow 3.0 InGeCoreFlow.qml\n"
            "singleton FlowIcons 3.0 FlowIcons.qml\n"
            "singleton InGeIconLibrary 3.0 InGeIconLibrary.qml\n"
        )
        foreach(_coreflow_tool_type IN LISTS _COREFLOW_QML_TOOL_TYPES)
            if(NOT _coreflow_tool_type STREQUAL "InGeCoreFlow"
               AND NOT _coreflow_tool_type STREQUAL "FlowIcons"
               AND NOT _coreflow_tool_type STREQUAL "InGeIconLibrary")
                string(APPEND _COREFLOW_QMLDIR_TEXT
                    "${_coreflow_tool_type} 3.0 ${_coreflow_tool_type}.qml\n")
            endif()
        endforeach()
        file(WRITE
            "${_COREFLOW_QML_TOOL_ROOT}/qmldir"
            "${_COREFLOW_QMLDIR_TEXT}"
        )

        if(MOBILE_QML_RESOURCES)
            list(REMOVE_DUPLICATES MOBILE_QML_RESOURCES)
            qt_add_qml_module(AppCalicatasMobile
                URI InGe.Mobile
                VERSION 1.0
                RESOURCE_PREFIX /
                QML_FILES
                    ${MOBILE_QML_FILES}
                RESOURCES
                    ${MOBILE_QML_RESOURCES}
                SOURCES
                    calicatadocument.h calicatadocument.cpp
                    docsops.h
                    src/documents/nothingdocuments.h
                    fsutil.h fsutil.cpp
            )
        else()
            qt_add_qml_module(AppCalicatasMobile
                URI InGe.Mobile
                VERSION 1.0
                RESOURCE_PREFIX /
                QML_FILES
                    ${MOBILE_QML_FILES}
                SOURCES
                    calicatadocument.h calicatadocument.cpp
                    docsops.h
                    src/documents/nothingdocuments.h
                    fsutil.h fsutil.cpp
            )
        endif()

        # Dock glass material (liquidglass.frag -> .qsb in the module resources).
        qt_add_shaders(AppCalicatasMobile "inge_dock_glass_shaders"
            PREFIX "/InGe/Mobile/shaders"
            BASE "qml/Mobile/shaders"
            # No GLSL override: ShaderEffect links this fragment stage with Qt's
            # built-in vertex stage, which only ships the default variants
            # (100 es,120,150). Adding "300 es" here made GLES 3 drivers pick
            # 300 es for the fragment and 100 es for the vertex, and Mali
            # rejects that program ("L0001 Shader languages do not match").
            FILES
                qml/Mobile/shaders/liquidglass.frag
        )

        if(ANDROID)
            # androiddeployqt/qmlimportscanner debe inspeccionar solamente el
            # arbol QML de la aplicacion. Usar la raiz del repositorio, que
            # tambien contiene thirdparty, docs y backups provoca falsos
            # errores de sintaxis en fragmentos que no forman parte del APK.
            set_property(TARGET AppCalicatasMobile PROPERTY
                QT_QML_ROOT_PATH "${MOBILE_QML_DIR}")
        endif()


        # ---------------------------------------------------------
        # V35.1 QML MODULE SOURCE OF TRUTH:
        # All mobile QML is packaged exactly once by qt_add_qml_module()
        # under URI InGe.Mobile. The old resources_mobile_raw.qrc is kept
        # in the repository only as historical material and is NOT linked.
        # This prevents duplicate QML copies and ambiguous URI resolution.
        # ---------------------------------------------------------
        message(STATUS "InGe+ V35.1 single QML module enabled: InGe.Mobile")

        # ---------------------------------------------------------
        # FASE 5.4: recursos reales Propuesta A usados por Fichas.
        # Mantiene prefijo QRC oficial: qrc:/ui/ingeplus/propuesta_a/...
        # ---------------------------------------------------------
        set(INGE_PROPA_F54_QRC "${CMAKE_CURRENT_SOURCE_DIR}/resources/ui/InGePlus_UI_Resources_PropuestaA_Fase54/fase54_iconos_reales_propuesta_a.qrc")
        if(EXISTS "${INGE_PROPA_F54_QRC}")
            target_sources(AppCalicatasMobile PRIVATE "${INGE_PROPA_F54_QRC}")
            message(STATUS "InGe+ Fase 5.4 UI resources enabled: ${INGE_PROPA_F54_QRC}")
        else()
            message(WARNING "No se encontro fase54_iconos_reales_propuesta_a.qrc. Los iconos Propuesta A no cargaran.")
        endif()


        # ---------------------------------------------------------
        # FASE UI 02: recursos limpios para nueva interfaz.
        # Prefijo QRC estable: qrc:/ui/v2/...
        # Todos los archivos referenciados existen como placeholders
        # para evitar errores por rutas faltantes durante la implementaciÃ³n.
        # ---------------------------------------------------------
        set(INGE_UI_V2_QRC "${CMAKE_CURRENT_SOURCE_DIR}/resources_mobile_ui_v2.qrc")
        if(EXISTS "${INGE_UI_V2_QRC}")
            target_sources(AppCalicatasMobile PRIVATE "${INGE_UI_V2_QRC}")
            message(STATUS "InGe+ UI V2 clean resources enabled: ${INGE_UI_V2_QRC}")
        else()
            message(WARNING "No se encontro resources_mobile_ui_v2.qrc. Los recursos UI V2 no cargaran.")
        endif()

        # ---------------------------------------------------------
        # OpenSSL Android para HTTPS/Supabase.
        # QT_ANDROID_EXTRA_LIBS es APPEND para conservar cualquier otra
        # biblioteca externa que ya tenga configurada el target.
        # ---------------------------------------------------------
        if(ANDROID)
            if(NOT ANDROID_ABI)
                message(FATAL_ERROR
                    "ANDROID_ABI no esta definido; no se puede seleccionar OpenSSL Android."
                )
            endif()

            file(TO_CMAKE_PATH "$ENV{LOCALAPPDATA}" _INGE_LOCALAPPDATA)
            set(INGE_OPENSSL_DIR
                "${_INGE_LOCALAPPDATA}/Android/Sdk/android_openssl/ssl_3/${ANDROID_ABI}"
            )
            set(INGE_OPENSSL_CRYPTO
                "${INGE_OPENSSL_DIR}/libcrypto_3.so"
            )
            set(INGE_OPENSSL_SSL
                "${INGE_OPENSSL_DIR}/libssl_3.so"
            )

            if(EXISTS "${INGE_OPENSSL_CRYPTO}" AND EXISTS "${INGE_OPENSSL_SSL}")
                set_property(
                    TARGET AppCalicatasMobile
                    APPEND
                    PROPERTY QT_ANDROID_EXTRA_LIBS
                    "${INGE_OPENSSL_CRYPTO}"
                    "${INGE_OPENSSL_SSL}"
                )
                message(STATUS "InGe+ OpenSSL Android: ${INGE_OPENSSL_DIR}")
            else()
                message(FATAL_ERROR
                    "Faltan libcrypto_3.so y libssl_3.so en ${INGE_OPENSSL_DIR}"
                )
            endif()
        endif()

        # ---------------------------------------------------------
        # ANDROID APK FIX:
        # androiddeployqt busca la librerÃ­a principal en:
        # android-build-AppCalicatasMobile/libs/<ABI>/libAppCalicatasMobile_<ABI>.so
        # En algunos builds de Qt Creator/CMake la librerÃ­a queda en el build root;
        # este paso la copia antes de ejecutar Build Android APK.
        # ---------------------------------------------------------
        if(ANDROID)
            if(NOT ANDROID_ABI)
                set(ANDROID_ABI "arm64-v8a")
            endif()

            set(ANDROID_DEPLOY_DIR
                "${CMAKE_CURRENT_BINARY_DIR}/android-build-AppCalicatasMobile"
            )

            add_custom_command(TARGET AppCalicatasMobile POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E make_directory
                    "${ANDROID_DEPLOY_DIR}/libs/${ANDROID_ABI}"
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "$<TARGET_FILE:AppCalicatasMobile>"
                    "${ANDROID_DEPLOY_DIR}/libs/${ANDROID_ABI}/$<TARGET_FILE_NAME:AppCalicatasMobile>"
                COMMENT "Copying AppCalicatasMobile .so for androiddeployqt"
            )
        endif()
        qt_import_qml_plugins(AppCalicatasMobile)



        # ---------------------------------------------------------
        # V38.15 ANDROID QML SCANNER HARDENING
        # qmlimportscanner must never receive the repository root as either
        # a rootPath or importPath. The repository contains thirdparty/docs
        # and may contain external backups with non-compilable QML snippets.
        # ---------------------------------------------------------
        if(ANDROID)
            set_property(TARGET AppCalicatasMobile PROPERTY
                QT_QML_ROOT_PATH "${MOBILE_QML_DIR}")

            get_property(_INGE_FINAL_QML_IMPORT_PATHS
                         TARGET AppCalicatasMobile
                         PROPERTY QT_QML_IMPORT_PATH)
            set(_INGE_FINAL_QML_IMPORT_PATHS_CLEAN "")
            file(TO_CMAKE_PATH "${CMAKE_CURRENT_SOURCE_DIR}" _INGE_SOURCE_ROOT_NORMALIZED)

            foreach(_INGE_QML_PATH IN LISTS _INGE_FINAL_QML_IMPORT_PATHS)
                file(TO_CMAKE_PATH "${_INGE_QML_PATH}" _INGE_QML_PATH_NORMALIZED)
                if(_INGE_QML_PATH_NORMALIZED STREQUAL _INGE_SOURCE_ROOT_NORMALIZED)
                    message(STATUS "InGe+ QML scanner: repository root removed from import paths")
                elseif(_INGE_QML_PATH_NORMALIZED MATCHES "/_backup[^/]*/?$")
                    message(STATUS "InGe+ QML scanner: backup path removed: ${_INGE_QML_PATH}")
                else()
                    list(APPEND _INGE_FINAL_QML_IMPORT_PATHS_CLEAN "${_INGE_QML_PATH}")
                endif()
            endforeach()

            list(REMOVE_DUPLICATES _INGE_FINAL_QML_IMPORT_PATHS_CLEAN)
            set_property(TARGET AppCalicatasMobile PROPERTY
                QT_QML_IMPORT_PATH "${_INGE_FINAL_QML_IMPORT_PATHS_CLEAN}")
        endif()

        qt_finalize_executable(AppCalicatasMobile)

    else()
        message(FATAL_ERROR "Para Mobile te recomiendo Qt6.")
    endif()

endif()
