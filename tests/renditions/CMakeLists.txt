cmake_minimum_required(VERSION 3.21)
project(RenditionChecks LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.9 REQUIRED COMPONENTS Core Gui Network)
add_subdirectory(../../thirdparty/QXlsx QXlsx)
add_executable(rendition-checks checks.cpp auth_link.cpp ../../src/cpp/renditionlocalstore.cpp ../../src/cpp/renditionlocalstore.h ../../src/cpp/renditionsnapshotexporter.cpp)
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

# Compila los adaptadores reales (repositorio, sync, bridge) fuera del empaquetado Android.
add_library(rendition-adapters OBJECT ../../src/cpp/renditionrepository.cpp ../../src/cpp/renditionsynccontroller.cpp ../../src/cpp/renditionflutterbridge.cpp)
target_include_directories(rendition-adapters PRIVATE ../.. ../../src/cpp)
target_link_libraries(rendition-adapters PRIVATE Qt6::Core Qt6::Gui Qt6::Network)

enable_testing()
add_test(NAME native-domain-outbox-and-exports COMMAND rendition-checks)
set_tests_properties(native-domain-outbox-and-exports PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
add_test(NAME shared-vectors-parity COMMAND rendition-parity "${CMAKE_CURRENT_SOURCE_DIR}/vectors")
add_test(NAME rpc-contract COMMAND rendition-contract)
