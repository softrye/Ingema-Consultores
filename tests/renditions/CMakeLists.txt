cmake_minimum_required(VERSION 3.21)
project(RenditionChecks LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.9 REQUIRED COMPONENTS Core Gui Network Qml Quick Test)
add_subdirectory(../../thirdparty/QXlsx QXlsx)
add_executable(rendition-checks checks.cpp auth_link.cpp ../../src/cpp/renditionlocalstore.cpp ../../src/cpp/renditionlocalstore_working.cpp ../../src/cpp/renditionlocalstore.h ../../src/cpp/renditionsnapshotexporter.cpp)
target_compile_definitions(rendition-checks PRIVATE INGE_HAS_QXLSX=1)
target_include_directories(rendition-checks PRIVATE ../.. ../../thirdparty/QXlsx/header)
target_compile_options(rendition-checks PRIVATE -ffunction-sections -fdata-sections)
target_link_options(rendition-checks PRIVATE -Wl,--gc-sections)
target_link_libraries(rendition-checks PRIVATE Qt6::Core Qt6::Gui QXlsx::QXlsx)

# Vectores compartidos Web/Android (vectors/) + interruptor IA + puerto InGe IA.
add_executable(rendition-parity parity.cpp)
target_include_directories(rendition-parity PRIVATE ../..)
target_link_libraries(rendition-parity PRIVATE Qt6::Core)

# Contrato RPC -> modelo nativo (proyectos, primario, respuestas parciales, totales).
add_executable(rendition-contract contract.cpp)
target_include_directories(rendition-contract PRIVATE ../..)
target_compile_options(rendition-contract PRIVATE -UNDEBUG)
target_link_libraries(rendition-contract PRIVATE Qt6::Core)

# Contrato Working Document (rendition_cloud_working_rows_v01): payload, CAS, idempotencia, sustentos.
add_executable(rendition-working-contract working_contract.cpp)
target_include_directories(rendition-working-contract PRIVATE ../..)
target_compile_options(rendition-working-contract PRIVATE -UNDEBUG)
target_link_libraries(rendition-working-contract PRIVATE Qt6::Core)

# P0 conectividad: fuente única de estado + efecto en el almacén real (pruebas A-D, F).
add_executable(rendition-connectivity connectivity.cpp auth_link.cpp ../../src/cpp/renditionlocalstore.cpp ../../src/cpp/renditionlocalstore_working.cpp ../../src/cpp/renditionlocalstore.h)
target_include_directories(rendition-connectivity PRIVATE ../.. ../../src/cpp)
target_link_libraries(rendition-connectivity PRIVATE Qt6::Core Qt6::Gui)

# Cola REAL (sync controller + almacén) con repositorio de prueba por costura de enlace.
add_executable(rendition-working-queue working_queue.cpp fake_repository.cpp fake_repository.h auth_link.cpp
    ../../src/cpp/renditionsynccontroller.cpp ../../src/cpp/renditionsynccontroller.h
    ../../src/cpp/renditionrepository.h
    ../../src/cpp/renditionlocalstore.cpp ../../src/cpp/renditionlocalstore_working.cpp ../../src/cpp/renditionlocalstore.h)
target_include_directories(rendition-working-queue PRIVATE ../.. ../../src/cpp)
target_link_libraries(rendition-working-queue PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Test)

# Compila los adaptadores reales (repositorio, sync, bridge) fuera del empaquetado Android.
add_library(rendition-adapters OBJECT ../../src/cpp/renditionrepository.cpp ../../src/cpp/renditionsynccontroller.cpp ../../src/cpp/renditionflutterbridge.cpp)
target_include_directories(rendition-adapters PRIVATE ../.. ../../src/cpp)
target_link_libraries(rendition-adapters PRIVATE Qt6::Core Qt6::Gui Qt6::Network)

# Adaptador de presentación (requestId, anti doble toque, reglas C++) + contratos de revisión.
add_executable(rendition-ui-controller ui_controller.cpp ../../src/cpp/renditionuicontroller.cpp ../../src/cpp/renditionuicontroller.h)
target_include_directories(rendition-ui-controller PRIVATE ../..)
target_link_libraries(rendition-ui-controller PRIVATE Qt6::Core Qt6::Test)

# Modelo centralizado de incidencias (auras A-F + panel Estado de Rendiciones).
add_executable(rendition-diagnostics diagnostics.cpp ../../src/cpp/renditionuicontroller.cpp ../../src/cpp/renditionuicontroller.h)
target_include_directories(rendition-diagnostics PRIVATE ../..)
target_link_libraries(rendition-diagnostics PRIVATE Qt6::Core Qt6::Test)

# Dock Contextual global REAL: contrato de 4 posiciones y tapCommand (3D Touch).
add_executable(rendition-dock-context dock_context.cpp ../../src/dock/DockContextController.cpp ../../src/dock/DockContextController.h)
target_include_directories(rendition-dock-context PRIVATE ../..)
target_link_libraries(rendition-dock-context PRIVATE Qt6::Core)

# Pantallas QML reales de la subapp con un bridge sintético (no Android, no Supabase).
add_executable(rendition-qml-flow qml_flow.cpp ../../src/cpp/renditionuicontroller.cpp ../../src/cpp/renditionuicontroller.h)
target_include_directories(rendition-qml-flow PRIVATE ../..)
target_link_libraries(rendition-qml-flow PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)

enable_testing()
add_test(NAME native-domain-outbox-and-exports COMMAND rendition-checks)
set_tests_properties(native-domain-outbox-and-exports PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
add_test(NAME shared-vectors-parity COMMAND rendition-parity "${CMAKE_CURRENT_SOURCE_DIR}/vectors")
add_test(NAME rpc-contract COMMAND rendition-contract)
add_test(NAME working-contract COMMAND rendition-working-contract)
add_test(NAME connectivity COMMAND rendition-connectivity)
add_test(NAME working-queue COMMAND rendition-working-queue)
set_tests_properties(working-queue PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
set_tests_properties(connectivity PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
add_test(NAME ui-controller COMMAND rendition-ui-controller)
add_test(NAME diagnostics COMMAND rendition-diagnostics)
add_test(NAME dock-context COMMAND rendition-dock-context)
add_test(NAME qml-flow COMMAND rendition-qml-flow "${CMAKE_CURRENT_SOURCE_DIR}/../../qml/Mobile/renditions")
set_tests_properties(qml-flow PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
