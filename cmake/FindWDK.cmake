# Redistribution and use is allowed under the OSI-approved 3-clause BSD license.
# Copyright (c) 2018 Sergey Podobry (sergey.podobry at gmail.com). All rights reserved.

#.rst:
# FindWDK
# ----------
#
# This module searches for the installed Windows Development Kit (WDK) and
# exposes commands for creating kernel drivers and kernel libraries.
#
# Output variables:
# - `WDK_FOUND` -- if false, do not try to use WDK
# - `WDK_ROOT` -- where WDK is installed
# - `WDK_VERSION` -- the version of the selected WDK
# - `WDK_WINVER` -- the WINVER used for kernel drivers and libraries
#        (default value is `0x0601` and can be changed per target or globally)
# - `WDK_NTDDI_VERSION` -- the NTDDI_VERSION used for kernel drivers and libraries,
#                          if not set, the value will be automatically calculated by WINVER
#        (default value is left blank and can be changed per target or globally)
#
# Example usage:
#
#   find_package(WDK REQUIRED)
#
#   wdk_add_kmd_library(KmdfCppLib STATIC KMDF 1.15
#       KmdfCppLib.h
#       KmdfCppLib.cpp
#       )
#   target_include_directories(KmdfCppLib INTERFACE .)
#
#   wdk_add_kmd_driver(KmdfCppDriver KMDF 1.15
#       Main.cpp
#       )
#   target_link_libraries(KmdfCppDriver KmdfCppLib)
#

# Thanks to yousif for this trick with the registry!
if(DEFINED ENV{WDKContentRoot})
    file(GLOB WDK_NTDDK_FILES
        "$ENV{WDKContentRoot}/Include/*/km/ntddk.h" # WDK 10
        "$ENV{WDKContentRoot}/Include/km/ntddk.h" # WDK 8.0, 8.1
    )
else()
    get_filename_component(WDK_ROOT
        "[HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows Kits\\Installed Roots;KitsRoot10]"
        ABSOLUTE)
    # Find all ntdkk.h files, then sort for the latest.
    file(GLOB WDK_NTDDK_FILES ${WDK_ROOT}/Include/*/km/ntddk.h)
endif()

if(WDK_NTDDK_FILES)
    if (NOT CMAKE_VERSION VERSION_LESS 3.18.0)
        list(SORT WDK_NTDDK_FILES COMPARE NATURAL) # sort to use the latest available WDK
    endif()
    list(GET WDK_NTDDK_FILES -1 WDK_LATEST_NTDDK_FILE)
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(WDK REQUIRED_VARS WDK_LATEST_NTDDK_FILE)

if (NOT WDK_LATEST_NTDDK_FILE)
    return()
endif()

get_filename_component(WDK_ROOT ${WDK_LATEST_NTDDK_FILE} DIRECTORY)
get_filename_component(WDK_ROOT ${WDK_ROOT} DIRECTORY)
get_filename_component(WDK_VERSION ${WDK_ROOT} NAME)
get_filename_component(WDK_ROOT ${WDK_ROOT} DIRECTORY)
if (NOT WDK_ROOT MATCHES ".*/[0-9][0-9.]*$") # WDK 10 has a deeper nesting level
    get_filename_component(WDK_ROOT ${WDK_ROOT} DIRECTORY) # go up once more
    set(WDK_LIB_VERSION "${WDK_VERSION}")
    set(WDK_INC_VERSION "${WDK_VERSION}")
else() # WDK 8.0, 8.1
    set(WDK_INC_VERSION "")
    foreach(VERSION winv6.3 win8 win7)
        if (EXISTS "${WDK_ROOT}/Lib/${VERSION}/")
            set(WDK_LIB_VERSION "${VERSION}")
            break()
        endif()
    endforeach()
    set(WDK_VERSION "${WDK_LIB_VERSION}")
endif()

message(STATUS "WDK_ROOT: ${WDK_ROOT}")
message(STATUS "WDK_VERSION: ${WDK_VERSION}")

# set(ENV{PATH} "${WDK_ROOT}/bin/${WDK_VERSION}/;$ENV{PATH}")
# message(STATUS "PATH: $ENV{PATH}")
message(STATUS "CMAKE_C_COMPILER: ${CMAKE_C_COMPILER}")
message(STATUS "CMAKE_CXX_COMPILER: ${CMAKE_CXX_COMPILER}")

find_program(WDK_TRACE_WPP_TOOL tracewpp
    HINTS "${WDK_ROOT}/bin"
    PATH_SUFFIXES
        "${WDK_VERSION}/x64"
        "${WDK_VERSION}/x86"
        "x64"
        "x86"
    REQUIRED
)
message(STATUS "WDK_TRACE_WPP_TOOL: ${WDK_TRACE_WPP_TOOL}")

find_program(WDK_INF2CATTOOL inf2cat
    HINTS "${WDK_ROOT}/bin"
    PATH_SUFFIXES
        "${WDK_VERSION}/x64"
        "${WDK_VERSION}/x86"
        "x64"
        "x86"
    REQUIRED
)
message(STATUS "WDK_INF2CATTOOL: ${WDK_INF2CATTOOL}")

find_program(WDK_STAMPINF_TOOL stampinf
    HINTS "${WDK_ROOT}/bin"
    PATH_SUFFIXES
        "${WDK_VERSION}/x64"
        "${WDK_VERSION}/x86"
        "x64"
        "x86"
    REQUIRED
)
message(STATUS "WDK_STAMPINF_TOOL: ${WDK_STAMPINF_TOOL}")

find_program(WDK_SIGNTOOL signtool
    HINTS "${WDK_ROOT}/bin"
    PATH_SUFFIXES
        "${WDK_VERSION}/x64"
        "${WDK_VERSION}/x86"
        "x64"
        "x86"
    REQUIRED
)
message(STATUS "WDK_SIGNTOOL: ${WDK_SIGNTOOL}")

get_filename_component(PACKAGE_DIR "${CMAKE_CURRENT_LIST_FILE}" PATH)
set(WDK_PFX "${PACKAGE_DIR}/TestSigning.pfx" CACHE STRING "Private key used for signing the driver")
if(NOT EXISTS "${WDK_PFX}")
    message(FATAL_ERROR "PFX not found: ${WDK_PFX}")
else()
    message(STATUS "PFX: ${WDK_PFX}")
endif()

# Windows 10 1709 by default
# https://learn.microsoft.com/ru-ru/cpp/porting/modifying-winver-and-win32-winnt
# https://learn.microsoft.com/en-us/windows/win32/winprog/using-the-windows-headers
set(WDK_WINVER "0x0A00" CACHE STRING "Default WINVER for WDK targets")
set(WDK_NTDDI_VERSION "0x0A000004" CACHE STRING "Specified NTDDI_VERSION for WDK targets if needed")

set(WDK_ADDITIONAL_FLAGS_FILE "${CMAKE_CURRENT_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/wdkflags.h")
file(WRITE ${WDK_ADDITIONAL_FLAGS_FILE} "#pragma runtime_checks(\"suc\", off)")

# location of warning.h
set(WDK_WARNING_H_FILE "${WDK_ROOT}/Include/${WDK_VERSION}/shared/warning.h")
set(WDK_COMPILE_FLAGS
        "/Zi"
        "/W4"
        "/WX"
        "/diagnostics:classic"
        "/Oy-"
        "/GF"
        "/Gm-"
        "/Zp8"
        "/GS"
        "/Gy"
        "/analyze-" 
        "/fp:precise"
        "/Zc:wchar_t-"
        "/Zc:forScope"
        "/Zc:inline"
        "/GR-"
        "/wd4603"
        "/wd4627"
        "/wd4986"
        "/wd4987"
        "/wd4996"
        "/wd4064"
        "/wd4366"
        "/wd4748"
        "/wd4047"
        "/wd4053"
        "/Wv:18"
        "/FC"
        "/errorReport:prompt"
        "-cbstring"
        # "-d2epilogunwind"
        "/d1nodatetime"
        "/d1import_no_registry"
        "/d2AllowCompatibleILVersions"
        "/d2Zi+"
        "/FI${WDK_WARNING_H_FILE}"
    )
list(APPEND WDK_COMPILE_FLAGS "$<$<CONFIG:Debug>:/Od>;$<$<CONFIG:Rlease>:/O2>")
# message(STATUS "WDK_COMPILE_FLAGS: " ${WDK_COMPILE_FLAGS})

set(WDK_COMPILE_DEFINITIONS "WINNT=1")
set(WDK_COMPILE_DEFINITIONS_DEBUG "MSC_NOOPT;DEPRECATE_DDK_FUNCTIONS=1;DBG=1")
set(CMAKE_RC_FLAGS "${CMAKE_RC_FLAGS} /I\"${WDK_ROOT}/Include/${WDK_INC_VERSION}/um\"")
if(TARGET_ARCH_X86)
    list(APPEND WDK_COMPILE_DEFINITIONS "_X86_=1;i386=1;STD_CALL")
    set(WDK_PLATFORM "x86")
    set(INF2CAT_OS_TYPE "10_X86")
    set(STAMPINF_ARCH_TYPE "x86")
elseif(TARGET_ARCH_X64)
    list(APPEND WDK_COMPILE_DEFINITIONS "_WIN64;_AMD64_;AMD64")
    set(WDK_PLATFORM "X64")
    set(INF2CAT_OS_TYPE "10_X64")
    set(STAMPINF_ARCH_TYPE "AMD64")
    elseif(TARGET_ARCH_ARM64)
    set(WDK_PLATFORM "arm64")
    list(APPEND WDK_COMPILE_DEFINITIONS "_WIN64;_ARM64_;ARM64")
    set(OS_TYPE "server10_arm64")
    set(INF2CAT_OS_TYPE "server10_arm64")
    set(STAMPINF_ARCH_TYPE "ARM64")
else()
        message(FATAL_ERROR "Unsupported architecture")
endif()

# EWDK Didn't Initilzie CMAKE_SIZEOF_VOID_P
if(NOT DEFINED CMAKE_SIZEOF_VOID_P)
    message(WARNING  "CMAKE_SIZEOF_VOID_P Not Defined, will be inferred by WDK_PLATFORM:${WDK_PLATFORM}")
    if(WDK_PLATFORM MATCHES 64)
        set(CMAKE_SIZEOF_VOID_P 8)
        else()
        set(CMAKE_SIZEOF_VOID_P 4)
    endif()
endif()

string(CONCAT WDK_LINK_FLAGS
    "/machine:${WDK_PLATFORM} "
    "/MANIFEST:NO "
    "/PROFILE "
    "/WX "
    "/Driver "
    "/OPT:REF "
    "/OPT:ICF "
    "/INCREMENTAL:NO "
    "/SUBSYSTEM:NATIVE,\"10.00\" "
    "/MERGE:\"_TEXT=.text;_PAGE=PAGE\" "
    "/NODEFAULTLIB "
    "/SECTION:INIT,d "
    "/IGNORE:4198,4010,4037,4039,4065,4070,4078,4087,4089,4221,4108,4088,4218,4218,4235,4257 "
    "/osversion:\"10.0\" " 
    "/version:\"10.0\" " 
    "/pdbcompress "
    "/debugtype:pdata "
    "/nologo "
)

# Generate imported targets for WDK lib files
file(GLOB WDK_LIBRARIES "${WDK_ROOT}/Lib/${WDK_LIB_VERSION}/km/${WDK_PLATFORM}/*.lib")
foreach(LIBRARY IN LISTS WDK_LIBRARIES)
get_filename_component(LIBRARY_NAME ${LIBRARY} NAME_WE)
string(TOUPPER ${LIBRARY_NAME} LIBRARY_NAME)
add_library(WDK::${LIBRARY_NAME} INTERFACE IMPORTED)
set_property(TARGET WDK::${LIBRARY_NAME} PROPERTY INTERFACE_LINK_LIBRARIES  ${LIBRARY})
endforeach(LIBRARY)
unset(WDK_LIBRARIES)
set(CMAKE_CXX_STANDARD_LIBRARIES " ")
set(CMAKE_C_STANDARD_LIBRARIES " ")

function(wdk_add_kmd_driver _target)

        cmake_parse_arguments(WDK "" "KMDF;WINVER;NTDDI_VERSION" "" ${ARGN})        
        add_executable(${_target} ${WDK_UNPARSED_ARGUMENTS})
        set_target_properties(${_target} PROPERTIES SUFFIX ".sys")

        if(DEFINED WDK_KMDF)
            string(REPLACE "." ";" WDK_KMDF_VER_LIST ${WDK_KMDF})
            list(GET WDK_KMDF_VER_LIST 0 KMDF_VERSION_MAJOR)
            list(GET WDK_KMDF_VER_LIST 1 KMDF_VERSION_MINOR)
            list(APPEND WDK_COMPILE_DEFINITIONS "KMDF_VERSION_MAJOR=${KMDF_VERSION_MAJOR}")
            list(APPEND WDK_COMPILE_DEFINITIONS "KMDF_VERSION_MINOR=${KMDF_VERSION_MINOR}")
        endif()

        list(APPEND WDK_COMPILE_FLAGS "/kernel")
        # set_target_properties(${_target} PROPERTIES COMPILE_OPTIONS "${WDK_COMPILE_FLAGS}")

        target_compile_options(${_target} PRIVATE
        $<$<COMPILE_LANGUAGE:C>:${C_DEFS} ${WDK_COMPILE_FLAGS}>
        $<$<COMPILE_LANGUAGE:CXX>:${CXX_DEFS} ${WDK_COMPILE_FLAGS}>
        $<$<COMPILE_LANGUAGE:ASM>:${ASM_FLAGS}>
        )

        set_target_properties(${_target} PROPERTIES COMPILE_DEFINITIONS
        "${WDK_COMPILE_DEFINITIONS};$<$<CONFIG:Debug>:${WDK_COMPILE_DEFINITIONS_DEBUG}>;_WIN32_WINNT=${WDK_WINVER};WINVER=${WDK_WINVER}"
        )
        # link parameter
        set_target_properties(${_target} PROPERTIES LINK_FLAGS "${WDK_LINK_FLAGS}")
        set_property(TARGET ${_target} APPEND_STRING PROPERTY LINK_FLAGS "/kernel ")

        if(WDK_NTDDI_VERSION)
        target_compile_definitions(${_target} PRIVATE NTDDI_VERSION=${WDK_NTDDI_VERSION})
        endif()
        
        target_include_directories(${_target} PRIVATE
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/shared"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/km"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/km/crt"
        )
        
        target_link_libraries(${_target} WDK::NTOSKRNL WDK::HAL WDK::BUFFEROVERFLOWFASTFAILK WDK::WMILIB WDK::WPPRECORDER WDK::BUFFEROVERFLOWFASTFAILK) 
        
        if(CMAKE_SIZEOF_VOID_P EQUAL 4)
            target_link_libraries(${_target} WDK::MEMCMP)
        endif()
        
        if(${WDK_PLATFORM} STREQUAL "arm64")
            target_link_libraries(${_target} "${WDK_ROOT}/Lib/${WDK_INC_VERSION}/um/${WDK_PLATFORM}/arm64rt.lib")
        endif()

        if(DEFINED WDK_KMDF)
            target_include_directories(${_target} PRIVATE "${WDK_ROOT}/Include/wdf/kmdf/${WDK_KMDF}")
            target_link_libraries(${_target}
            "${WDK_ROOT}/Lib/wdf/kmdf/${WDK_PLATFORM}/${WDK_KMDF}/WdfDriverEntry.lib"
            "${WDK_ROOT}/Lib/wdf/kmdf/${WDK_PLATFORM}/${WDK_KMDF}/WdfLdr.lib"
            )
            if(CMAKE_SIZEOF_VOID_P EQUAL 4)
                set_property(TARGET ${_target} APPEND_STRING PROPERTY LINK_FLAGS "/ENTRY:FxDriverEntry@8")
            elseif(CMAKE_SIZEOF_VOID_P  EQUAL 8)
                set_property(TARGET ${_target} APPEND_STRING PROPERTY LINK_FLAGS "/ENTRY:FxDriverEntry")
            endif()
        else()
            if(CMAKE_SIZEOF_VOID_P EQUAL 4)
                set_property(TARGET ${_target} APPEND_STRING PROPERTY LINK_FLAGS "/ENTRY:GsDriverEntry@8")
            elseif(CMAKE_SIZEOF_VOID_P  EQUAL 8)
                set_property(TARGET ${_target} APPEND_STRING PROPERTY LINK_FLAGS "/ENTRY:GsDriverEntry")
            endif()
        endif()
    
    # copy inf
    add_custom_command(
        TARGET ${_target} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/${_target}.inx ${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>/${_target}.inf
        VERBATIM
    )
    #timestamp inf stage
    add_custom_command(
        TARGET ${_target} POST_BUILD
        COMMAND ${WDK_STAMPINF_TOOL}  -a ${STAMPINF_ARCH_TYPE} -v "*" -k "1.15"  -d "*" -x -f "${CMAKE_CURRENT_BINARY_DIR}\\$<CONFIG>\\${_target}.inf"
        VERBATIM
        )
    # #inf2cat stage
    # add_custom_command(
    #     TARGET ${_target} POST_BUILD
    #     COMMAND ${WDK_INF2CATTOOL}  /os:${INF2CAT_OS_TYPE} /driver:${CMAKE_CURRENT_BINARY_DIR}/$<CONFIG>
    #     VERBATIM
    # )
    # Code signing
    add_custom_command(
        TARGET ${_target} POST_BUILD
        COMMAND "${WDK_SIGNTOOL}" sign /fd SHA256 /f "${WDK_PFX}" "$<TARGET_FILE:${_target}>"
        VERBATIM
    )
endfunction()

function(wdk_add_kmd_library _target)

    cmake_parse_arguments(WDK "" "KMDF;WINVER;NTDDI_VERSION" "" ${ARGN})
    message(STATUS "Target: " ${_target})
    message(STATUS "WDK_KMDF: " ${WDK_KMDF})
    message(STATUS "WDK_WINVER: " ${WDK_WINVER})
    message(STATUS "WDK_NTDDI_VERSION: " ${WDK_NTDDI_VERSION})

    add_library(${_target} ${WDK_UNPARSED_ARGUMENTS})

    if(DEFINED WDK_KMDF)
        string(REPLACE "." ";" WDK_KMDF_VER_LIST ${WDK_KMDF})
        list(GET WDK_KMDF_VER_LIST 0 KMDF_VERSION_MAJOR)
        list(GET WDK_KMDF_VER_LIST 1 KMDF_VERSION_MINOR)
        list(APPEND WDK_COMPILE_DEFINITIONS "KMDF_VERSION_MAJOR=${KMDF_VERSION_MAJOR}")
        list(APPEND WDK_COMPILE_DEFINITIONS "KMDF_VERSION_MINOR=${KMDF_VERSION_MINOR}")
    endif()


    list(APPEND WDK_COMPILE_FLAGS "/kernel")
    # set_target_properties(${_target} PROPERTIES COMPILE_OPTIONS "${WDK_COMPILE_FLAGS}")
    target_compile_options(${_target} PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${C_DEFS} ${WDK_COMPILE_FLAGS}>
    $<$<COMPILE_LANGUAGE:CXX>:${CXX_DEFS} ${WDK_COMPILE_FLAGS}>
    $<$<COMPILE_LANGUAGE:ASM>:-x assembler-with-cpp ${ASM_FLAGS}>
    )

    set_property(TARGET ${_target} APPEND PROPERTY COMPILE_DEFINITIONS
    "${WDK_COMPILE_DEFINITIONS};$<$<CONFIG:Debug>:${WDK_COMPILE_DEFINITIONS_DEBUG};>_WIN32_WINNT=${WDK_WINVER};WINVER=${WDK_WINVER}"
    )
    if(WDK_NTDDI_VERSION)
        target_compile_definitions(${_target} PRIVATE NTDDI_VERSION=${WDK_NTDDI_VERSION})
    endif()

    target_include_directories(${_target} SYSTEM PRIVATE
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/shared"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/km"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/km/crt"
        )

    if(DEFINED WDK_KMDF)
        target_include_directories(${_target} SYSTEM PRIVATE "${WDK_ROOT}/Include/wdf/kmdf/${WDK_KMDF}")
    endif()
endfunction()

function(wdk_add_umd_library _target)

    cmake_parse_arguments(WDK "" "UMDF;WINVER;NTDDI_VERSION" "" ${ARGN})
    message(STATUS "Target: " ${_target})
    message(STATUS "WDK_UMDF: " ${WDK_UMDF})
    message(STATUS "WDK_WINVER: " ${WDK_WINVER})
    message(STATUS "WDK_NTDDI_VERSION: " ${WDK_NTDDI_VERSION})

    add_library(${_target} ${WDK_UNPARSED_ARGUMENTS})

    if(DEFINED WDK_UMDF)
        string(REPLACE "." ";" WDK_UMDF_VER_LIST ${WDK_UMDF})
        list(GET WDK_UMDF_VER_LIST 0 UMDF_VERSION_MAJOR)
        list(GET WDK_UMDF_VER_LIST 1 UMDF_VERSION_MINOR)
    endif()

    list(APPEND WDK_COMPILE_DEFINITIONS "UMDF_VERSION_MAJOR=${UMDF_VERSION_MAJOR}")
    list(APPEND WDK_COMPILE_DEFINITIONS "UMDF_VERSION_MINOR=${UMDF_VERSION_MINOR}")

    target_compile_options(${_target} PRIVATE
    $<$<COMPILE_LANGUAGE:C>:${C_DEFS} ${WDK_COMPILE_FLAGS}>
    $<$<COMPILE_LANGUAGE:CXX>:${CXX_DEFS} ${WDK_COMPILE_FLAGS}>
    $<$<COMPILE_LANGUAGE:ASM>: ${ASM_FLAGS}>
    )

    set_property(TARGET ${_target} APPEND PROPERTY COMPILE_DEFINITIONS
    "${WDK_COMPILE_DEFINITIONS};$<$<CONFIG:Debug>:${WDK_COMPILE_DEFINITIONS_DEBUG};>_WIN32_WINNT=${WDK_WINVER}"
    )
    if(WDK_NTDDI_VERSION)
        target_compile_definitions(${_target} PRIVATE NTDDI_VERSION=${WDK_NTDDI_VERSION})
    endif()

    target_include_directories(${_target} SYSTEM PRIVATE
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/shared"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/winrt"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/ucrt"
        "${WDK_ROOT}/Include/${WDK_INC_VERSION}/um"
        )

    if(DEFINED WDK_UMDF)
        target_include_directories(${_target} SYSTEM PRIVATE "${WDK_ROOT}/Include/wdf/umdf/${WDK_UMDF}")
    endif()
endfunction()

function(wdk_add_usermode_driver _target)
    cmake_parse_arguments(WDK "" "UMDF;WINVER;NTDDI_VERSION" "" ${ARGN})

    message(STATUS "UMDF_VERSION_MAJOR: ${UMDF_VERSION_MAJOR}")
    message(STATUS "WDK_UMDF: " ${WDK_UMDF})
    message(STATUS "UMDF_VERSION_MAJOR : " ${UMDF_VERSION_MAJOR})
    message(STATUS "WDK_WINVER: " ${WDK_WINVER})
    message(STATUS "WDK_NTDDI_VERSION: " ${WDK_NTDDI_VERSION})

    add_library(${_target} ${WDK_UNPARSED_ARGUMENTS})

    set_target_properties(${_target} PROPERTIES SUFFIX ".dll")
    set_target_properties(${_target} PROPERTIES COMPILE_OPTIONS "/Gz")
    set_target_properties(${_target} PROPERTIES COMPILE_DEFINITIONS
        "${WDK_COMPILE_DEFINITIONS};_WIN32_WINNT=${WDK_WINVER};NTDDI_VERSION=${WDK_NTDDI_VERSION}")
    set_target_properties(${_target} PROPERTIES LINK_FLAGS "/SUBSYSTEM:WINDOWS")

    set(WDK_WDF_DIR "${WDK_WDF_ROOT}/wdf/umdf/${WDK_UMDF}")
    set(WDK_WINRT_DIR "${WDK_ROOT}/Include/${WDK_INC_VERSION}/winrt")
    set(WDK_UCRT_DIR "${WDK_ROOT}/Include/${WDK_INC_VERSION}/ucrt")
    set(WDK_SHARED_DIR "${WDK_ROOT}/Include/${WDK_INC_VERSION}/shared")
    set(WDK_UM_DIR "${WDK_ROOT}/Include/${WDK_INC_VERSION}/um")
    set(WDK_IDDCX_DIR "${WDK_ROOT}/Include/${WDK_INC_VERSION}/um/iddcx/${IDDCX_VERSION_MAJOR}.${IDDCX_VERSION_MINOR}")

    target_include_directories(${_target} SYSTEM PRIVATE
        "${WDK_WDF_DIR}"
        "${WDK_WINRT_DIR}"
        "${WDK_UCRT_DIR}"
        "${WDK_SHARED_DIR}"
        "${WDK_UM_DIR}"
        "${WDK_IDDCX_DIR}")

    message(STATUS "WDK_WDF_DIR: ${WDK_WDF_DIR}")
    message(STATUS "WDK_WINRT_DIR: ${WDK_WINRT_DIR}")
    message(STATUS "WDK_UCRT_DIR: ${WDK_UCRT_DIR}")
    message(STATUS "WDK_SHARED_DIR: ${WDK_SHARED_DIR}")
    message(STATUS "WDK_UM_DIR: ${WDK_UM_DIR}")
    message(STATUS "WDK_IDDCX_DIR: ${WDK_IDDCX_DIR}")

    target_link_libraries(${_target} OneCoreUAP avrt)
endfunction()

function(kmd_wpp_preproc _target wpp_source_files source_dir scan_config_data)

    set(WPP_CONFIGDIR ${WDK_ROOT}/bin/${WDK_INC_VERSION}/WppConfig/Rev1)
    add_custom_command(
        TARGET ${_target} PRE_BUILD
        COMMAND ${WDK_TRACE_WPP_TOOL} -cfgdir:${WPP_CONFIGDIR} -odir:${source_dir} -scan:${scan_config_data} -km ${wpp_source_files}
        VERBATIM
    )

endfunction()

function(umd_wpp_preproc _target wpp_source_files source_dir scan_config_data)

    set(WPP_CONFIGDIR ${WDK_ROOT}/bin/${WDK_INC_VERSION}/WppConfig/Rev1)
    add_custom_command(
        TARGET ${_target} PRE_BUILD
        COMMAND ${WDK_TRACE_WPP_TOOL} -cfgdir:${WPP_CONFIGDIR} -odir:${source_dir} -scan:${scan_config_data} -dll ${wpp_source_files}
        VERBATIM
    )

endfunction()

function(wdk_etw_preproc _target etw_name source_dir)

    # message("wpp_source_files "${wpp_source_files})    
    set(WPP_CONFIGDIR ${WDK_ROOT}/bin/${WDK_INC_VERSION}/WppConfig/Rev1)
    # Code signing
    add_custom_command(
        TARGET ${_target} PRE_BUILD
        COMMAND ${WDK_ROOT}/bin/${WDK_INC_VERSION}/x64/mc.exe  -h ${source_dir} -km -r ${source_dir} -z ${etw_name} ${source_dir}/${etw_name}.xml
        VERBATIM
    )

endfunction()