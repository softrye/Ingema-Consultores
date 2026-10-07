#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "QMapLibre::Location" for configuration "RelWithDebInfo"
set_property(TARGET QMapLibre::Location APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(QMapLibre::Location PROPERTIES
  IMPORTED_LINK_DEPENDENT_LIBRARIES_RELWITHDEBINFO "QMapLibre::QuickPrivate;Qt6::Network"
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/lib/libQMapLibreLocation_arm64-v8a.so"
  IMPORTED_SONAME_RELWITHDEBINFO "libQMapLibreLocation_arm64-v8a.so"
  )

list(APPEND _cmake_import_check_targets QMapLibre::Location )
list(APPEND _cmake_import_check_files_for_QMapLibre::Location "${_IMPORT_PREFIX}/lib/libQMapLibreLocation_arm64-v8a.so" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
