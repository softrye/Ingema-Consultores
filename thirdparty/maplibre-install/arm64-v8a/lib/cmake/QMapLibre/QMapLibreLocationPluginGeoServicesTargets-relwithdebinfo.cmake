#----------------------------------------------------------------
# Generated CMake target import file for configuration "RelWithDebInfo".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "QMapLibre::PluginGeoServices" for configuration "RelWithDebInfo"
set_property(TARGET QMapLibre::PluginGeoServices APPEND PROPERTY IMPORTED_CONFIGURATIONS RELWITHDEBINFO)
set_target_properties(QMapLibre::PluginGeoServices PROPERTIES
  IMPORTED_COMMON_LANGUAGE_RUNTIME_RELWITHDEBINFO ""
  IMPORTED_LOCATION_RELWITHDEBINFO "${_IMPORT_PREFIX}/plugins/geoservices/libplugins_geoservices_qtgeoservices_maplibre_arm64-v8a.so"
  IMPORTED_NO_SONAME_RELWITHDEBINFO "TRUE"
  )

list(APPEND _cmake_import_check_targets QMapLibre::PluginGeoServices )
list(APPEND _cmake_import_check_files_for_QMapLibre::PluginGeoServices "${_IMPORT_PREFIX}/plugins/geoservices/libplugins_geoservices_qtgeoservices_maplibre_arm64-v8a.so" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
