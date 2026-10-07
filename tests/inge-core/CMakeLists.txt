cmake_minimum_required(VERSION 3.16)
project(InGeCoreContract LANGUAGES CXX)

# Standalone contract/observer validation. Does not configure the Android application.
# cmake -S tests/inge-core -B <temporary-directory> -DCMAKE_PREFIX_PATH=<Qt-kit>
# cmake --build <temporary-directory>
# ctest --test-dir <temporary-directory> --output-on-failure
find_package(Qt6 6.9.3 REQUIRED COMPONENTS Core Qml)
enable_testing()

foreach(mode IN ITEMS default disabled enabled)
    add_executable(inge_core_${mode}
        inge_core_contract_test.cpp
        ../../src/core/InGeCore.cpp)
    target_compile_features(inge_core_${mode} PRIVATE cxx_std_17)
    target_link_libraries(inge_core_${mode} PRIVATE Qt6::Core Qt6::Qml)
    if(mode STREQUAL "enabled")
        target_compile_definitions(inge_core_${mode} PRIVATE INGE_CORE_ENABLED=1)
    elseif(mode STREQUAL "disabled")
        target_compile_definitions(inge_core_${mode} PRIVATE INGE_CORE_ENABLED=0)
    endif()
    add_test(NAME inge_core_${mode} COMMAND inge_core_${mode})
endforeach()
