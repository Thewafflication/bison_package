cmake_minimum_required(VERSION 3.24)
project(bison_package LANGUAGES C)

include(CTest)

set(BISON_ARCH "x64" CACHE STRING "Target architecture: x86, x64, or arm64")
set_property(CACHE BISON_ARCH PROPERTY STRINGS x86 x64 arm64)
set(BISON_PACKAGE_VERSION "3.8.2" CACHE STRING "Semantic WPM package version")
if(NOT BISON_ARCH MATCHES "^(x86|x64|arm64)$")
  message(FATAL_ERROR "BISON_ARCH must be x86, x64, or arm64")
endif()
if(NOT CMAKE_C_COMPILER_ID STREQUAL "TinyCC")
  message(FATAL_ERROR "This project must be configured with WPM TinyCC")
endif()

find_program(BISON_POWERSHELL NAMES powershell.exe pwsh.exe pwsh REQUIRED)
if(DEFINED ENV{WPM_WCRT_ROOT} AND NOT "$ENV{WPM_WCRT_ROOT}" STREQUAL "")
  file(TO_CMAKE_PATH "$ENV{WPM_WCRT_ROOT}" BISON_WCRT_ROOT)
else()
  file(TO_CMAKE_PATH "$ENV{ProgramFiles}/WCRT" _bison_wcrt_install_root)
  file(GLOB _bison_wcrt_versions LIST_DIRECTORIES TRUE "${_bison_wcrt_install_root}/*")
  list(SORT _bison_wcrt_versions COMPARE NATURAL ORDER DESCENDING)
  foreach(_candidate IN LISTS _bison_wcrt_versions)
    if(EXISTS "${_candidate}/include/stdio.h" AND
       EXISTS "${_candidate}/${BISON_ARCH}/lib/libwcrt.a")
      set(BISON_WCRT_ROOT "${_candidate}")
      break()
    endif()
  endforeach()
endif()
if(NOT BISON_WCRT_ROOT)
  message(FATAL_ERROR "WPM WCRT was not found; install wcrt or set WPM_WCRT_ROOT")
endif()

set(BISON_SOURCE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/out/source/bison-3.8.2")
set(BISON_SOURCE_STAMP "${BISON_SOURCE_ROOT}/.bison-wcrt-source")
set(BISON_HOST_TOOLS_STAMP "${CMAKE_CURRENT_SOURCE_DIR}/out/host-tools/.prepared")
set(BISON_UPSTREAM_BUILD "${CMAKE_BINARY_DIR}/upstream")
set(BISON_EXECUTABLE "${BISON_UPSTREAM_BUILD}/src/bison.exe")
set(BISON_M4_RUNTIME "${CMAKE_CURRENT_SOURCE_DIR}/out/host-tools/runtime/bin")

add_custom_command(
  OUTPUT "${BISON_SOURCE_STAMP}"
  COMMAND "${BISON_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/Get-BisonSource.ps1"
  DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/Get-BisonSource.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/patches/bison-3.8.2-wcrt.patch"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Downloading, verifying, and patching GNU Bison 3.8.2"
  VERBATIM
)
add_custom_command(
  OUTPUT "${BISON_HOST_TOOLS_STAMP}"
  COMMAND "${BISON_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/Get-HostTools.ps1"
  DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tools/Get-HostTools.ps1"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Preparing pinned GNU Make and M4 host tools"
  VERBATIM
)
add_custom_target(download-sources
  DEPENDS "${BISON_SOURCE_STAMP}" "${BISON_HOST_TOOLS_STAMP}")

add_custom_command(
  OUTPUT "${BISON_EXECUTABLE}"
  COMMAND "${BISON_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/Build-Bison.ps1"
    -Architecture "${BISON_ARCH}"
    -SourceDirectory "${BISON_SOURCE_ROOT}"
    -BuildDirectory "${BISON_UPSTREAM_BUILD}"
    -TinyCcRoot "${BISON_TCC_ROOT}"
    -WcrtRoot "${BISON_WCRT_ROOT}"
  DEPENDS
    "${BISON_SOURCE_STAMP}"
    "${BISON_HOST_TOOLS_STAMP}"
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/Build-Bison.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/build-bison.sh"
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/Patch-GnulibHeaders.ps1"
    "${CMAKE_CURRENT_SOURCE_DIR}/compat/direct.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/compat/io.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/compat/process.h"
    "${CMAKE_CURRENT_SOURCE_DIR}/compat/wcrt_compat.c"
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Building GNU Bison with TinyCC and WCRT for ${BISON_ARCH}"
  VERBATIM
)
add_custom_target(bison ALL DEPENDS "${BISON_EXECUTABLE}")

if(BUILD_TESTING)
  add_test(NAME bison-wcrt-smoke
    COMMAND "${BISON_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass
      -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/Test-Bison.ps1"
      -Bison "${BISON_EXECUTABLE}"
      -DataDirectory "${BISON_SOURCE_ROOT}/data"
      -M4Directory "${BISON_M4_RUNTIME}"
      -TestDirectory "${CMAKE_BINARY_DIR}/tests/smoke")
endif()

install(PROGRAMS "${BISON_EXECUTABLE}" DESTINATION bin)
install(PROGRAMS "${BISON_M4_RUNTIME}/m4.exe" DESTINATION bin)
install(FILES
  "${BISON_M4_RUNTIME}/msys-2.0.dll"
  "${BISON_M4_RUNTIME}/msys-intl-8.dll"
  "${BISON_M4_RUNTIME}/msys-iconv-2.dll"
  DESTINATION bin)
install(DIRECTORY "${BISON_SOURCE_ROOT}/data/" DESTINATION share/bison)
install(FILES "${BISON_SOURCE_ROOT}/COPYING" DESTINATION share/licenses/bison)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/out/host-tools/m4/usr/share/licenses/m4/COPYING"
  DESTINATION share/licenses/m4)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/README.md" DESTINATION share/doc/bison)

add_custom_target(wpm-package
  COMMAND "${CMAKE_COMMAND}" --install "${CMAKE_BINARY_DIR}"
  COMMAND "${BISON_POWERSHELL}" -NoProfile -ExecutionPolicy Bypass
    -File "${CMAKE_CURRENT_SOURCE_DIR}/tools/Build-WpmPackage.ps1"
    -Architecture "${BISON_ARCH}"
    -Version "${BISON_PACKAGE_VERSION}"
    -InstallRoot "${CMAKE_INSTALL_PREFIX}"
  DEPENDS bison
  WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
  COMMENT "Creating the ${BISON_ARCH} WPM package"
  VERBATIM)

message(STATUS "Bison target architecture: ${BISON_ARCH}")
message(STATUS "TinyCC root: ${BISON_TCC_ROOT}")
message(STATUS "WCRT root: ${BISON_WCRT_ROOT}")

