find_package(Qt6 6.9.3 REQUIRED COMPONENTS Core Gui Qml Quick Concurrent Network ShaderTools)
qt_add_qml_module(InGeRetroplasma STATIC
    URI InGe.Retroplasma
    VERSION 1.0
    CLASS_NAME InGeRetroplasmaPlugin
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/InGe/Retroplasma"
    RESOURCE_PREFIX /qt/qml
    SOURCES
        RetroplasmaMath.h RetroplasmaMath.cpp
        RetroplasmaPlanet.h RetroplasmaPlanet.cpp
        RetroplasmaPlanetProvider.h RetroplasmaPlanetProvider.cpp
        RetroplasmaCamera.h RetroplasmaCamera.cpp
        RetroplasmaGeometryDecoder.h RetroplasmaGeometryDecoder.cpp
        RetroplasmaTextureDecoder.h RetroplasmaTextureDecoder.cpp
        RetroplasmaScene.h
        RetroplasmaDataProvider.h RetroplasmaDataProvider.cpp
        RetroplasmaTileScheduler.h RetroplasmaTileScheduler.cpp
        RetroplasmaController.h RetroplasmaController.cpp
        RetroplasmaItem.h RetroplasmaItem.cpp
)
target_include_directories(InGeRetroplasma PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(InGeRetroplasma PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Concurrent Qt6::Network PRIVATE Qt6::GuiPrivate)
target_compile_features(InGeRetroplasma PUBLIC cxx_std_17)
qt_add_shaders(InGeRetroplasma rp_shaders
    PREFIX /inge/retroplasma
    GLSL "100es,300es,120,150"
    HLSL 50
    MSL 12
    FILES shaders/terrain.vert shaders/terrain.frag
)
# Explicit source resources; no network content or generated frames.
file(GLOB RP_SAMPLE_ASSETS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/resources/sample/*" "${CMAKE_CURRENT_SOURCE_DIR}/resources/earth/*")
qt_add_resources(InGeRetroplasma rp_samples
    PREFIX /inge/retroplasma
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources"
    FILES ${RP_SAMPLE_ASSETS}
)
