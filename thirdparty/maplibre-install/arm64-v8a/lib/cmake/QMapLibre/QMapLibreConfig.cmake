
####### Expanded from @PACKAGE_INIT@ by configure_package_config_file() #######
####### Any changes to this file will be overwritten by the next CMake run ####
####### The input file was config.cmake.in                            ########

get_filename_component(PACKAGE_PREFIX_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../" ABSOLUTE)

macro(set_and_check _var _file)
  set(${_var} "${_file}")
  if(NOT EXISTS "${_file}")
    message(FATAL_ERROR "File or directory ${_file} referenced by variable ${_var} does not exist !")
  endif()
endmacro()

####################################################################################

include(CMakeFindDependencyMacro)

set(_QMapLibre_supported_components Core;QuickPrivate;Location;Widgets)

foreach(_comp ${QMapLibre_FIND_COMPONENTS})
    if(NOT _comp IN_LIST _QMapLibre_supported_components)
        set(QMapLibre_FOUND False)
        set(QMapLibre_NOT_FOUND_MESSAGE "Unsupported component: ${_comp}")
    endif()

    if(_comp STREQUAL Core)
        find_dependency(Qt6 COMPONENTS Gui Network)
        if(NOT OFF)
            find_dependency(Qt6 COMPONENTS Sql)
        endif()

        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}Targets.cmake")
    elseif(_comp STREQUAL Quick)
        find_dependency(QMapLibre COMPONENTS QuickPrivate)

        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibreQuickMacros.cmake")
        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibreQuickPluginQmlTargets.cmake")
    elseif(_comp STREQUAL QuickPrivate)
        find_dependency(QMapLibre COMPONENTS Core)

        find_dependency(Qt6 COMPONENTS Quick)

        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}Targets.cmake")
    elseif(_comp STREQUAL Location)
        find_dependency(QMapLibre COMPONENTS Core QuickPrivate)

        find_dependency(Qt6 COMPONENTS Location)

        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}Targets.cmake")
        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}Macros.cmake")
        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}PluginGeoServicesTargets.cmake")
        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}PluginQmlTargets.cmake")
    elseif(_comp STREQUAL Widgets)
        find_dependency(QMapLibre COMPONENTS Core)

        find_dependency(Qt6 COMPONENTS Widgets)

        include("${CMAKE_CURRENT_LIST_DIR}/QMapLibre${_comp}Targets.cmake")
    endif()
endforeach()
