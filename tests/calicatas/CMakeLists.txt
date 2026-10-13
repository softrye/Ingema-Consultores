cmake_minimum_required(VERSION 3.21)
project(CalicatasP0Checks LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
find_package(Qt6 6.9.3 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Test)
set(ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
add_subdirectory("${ROOT}/thirdparty/QXlsx" QXlsx)
add_executable(calicatas_checks checks.cpp auth_link.cpp
    "${ROOT}/calicatadocument.cpp" "${ROOT}/calicatadocument.h"
    "${ROOT}/androidcalicataexporter.cpp" "${ROOT}/androidcalicataexporter.h"
    "${ROOT}/src/cpp/renditionsnapshotexporter.cpp"
    resources.qrc)
target_compile_definitions(calicatas_checks PRIVATE INGE_MOBILE INGE_HAS_QXLSX)
target_include_directories(calicatas_checks PRIVATE "${ROOT}")
target_link_libraries(calicatas_checks PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Test QXlsx::QXlsx)
