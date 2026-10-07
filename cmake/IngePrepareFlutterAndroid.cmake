# Flutter 3.44.9 generates an ephemeral Android wrapper with compileSdk 36.
# Current pinned plugins publish AAR metadata that requires API 37, matching
# the Qt Android host. Regenerate first with `flutter pub get`, then normalize
# only the generated compileSdk entries before `flutter build aar --no-pub`.

if(NOT DEFINED INGE_FLUTTER_ANDROID_DIR)
    message(FATAL_ERROR "INGE_FLUTTER_ANDROID_DIR is required")
endif()

set(_inge_flutter_gradle_files
    "${INGE_FLUTTER_ANDROID_DIR}/build.gradle"
    "${INGE_FLUTTER_ANDROID_DIR}/app/build.gradle"
    "${INGE_FLUTTER_ANDROID_DIR}/Flutter/build.gradle")

foreach(_inge_gradle_file IN LISTS _inge_flutter_gradle_files)
    if(NOT EXISTS "${_inge_gradle_file}")
        message(FATAL_ERROR
            "Flutter Android wrapper was not generated: ${_inge_gradle_file}")
    endif()

    file(READ "${_inge_gradle_file}" _inge_gradle_content)
    string(REGEX MATCH
        "compileSdk[ \t]*=[ \t]*(flutter\\.compileSdkVersion|[0-9]+)"
        _inge_compile_sdk_entry
        "${_inge_gradle_content}")
    if(NOT _inge_compile_sdk_entry)
        message(FATAL_ERROR
            "No compileSdk entry found in ${_inge_gradle_file}")
    endif()

    string(REGEX REPLACE
        "compileSdk[ \t]*=[ \t]*(flutter\\.compileSdkVersion|[0-9]+)"
        "compileSdk = 37"
        _inge_gradle_updated
        "${_inge_gradle_content}")

    if(NOT _inge_gradle_updated STREQUAL _inge_gradle_content)
        file(WRITE "${_inge_gradle_file}" "${_inge_gradle_updated}")
    endif()
endforeach()

message(STATUS "Flutter Android wrapper compileSdk fixed at API 37")
