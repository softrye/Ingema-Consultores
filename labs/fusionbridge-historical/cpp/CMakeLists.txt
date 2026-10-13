# Part of AppCalicatasMobile: no additional executable, APK or QML registration.
add_library(InGeFusionBridgeNative STATIC
    FusionBridgeController.cpp
    FusionBridgeController.h
)
target_link_libraries(InGeFusionBridgeNative PUBLIC Qt6::Core Qt6::Gui Qt6::Quick)
target_include_directories(InGeFusionBridgeNative PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
