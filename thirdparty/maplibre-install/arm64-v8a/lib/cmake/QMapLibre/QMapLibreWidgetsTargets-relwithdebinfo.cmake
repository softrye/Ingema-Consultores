#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "QMapLibre::Widgets" for configuration "RelWithDebInfo"
set_property(TARGET QMapLibre::Widgets APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(QMapLibre::Widgets PROPERTIES
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/libQMapLibreWidgets_arm64-v8a.so"
  IMPORTED_SONAME_RELWITHDEBINFO "libQMapLibreWidgets_arm64-v8a.so"
  )

list(APPEND _cmake_import_check_targets QMapLibre::Widgets )
list(APPEND _cmake_import_check_files_for_QMapLibre::Widgets "${_IMPORT_PREFIX}/lib/libQMapLibreWidgets_arm64-v8a.so" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
