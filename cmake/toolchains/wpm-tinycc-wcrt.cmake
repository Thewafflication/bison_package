set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

if(NOT DEFINED BISON_ARCH)
  set(BISON_ARCH x64)
endif()

if(BISON_ARCH STREQUAL "x86")
  set(_bison_tcc_driver i386-win32-tcc.exe)
  set(CMAKE_SYSTEM_PROCESSOR x86)
elseif(BISON_ARCH STREQUAL "x64")
  set(_bison_tcc_driver x86_64-win32-tcc.exe)
  set(CMAKE_SYSTEM_PROCESSOR AMD64)
elseif(BISON_ARCH STREQUAL "arm64")
  set(_bison_tcc_driver arm64-win32-tcc.exe)
  set(CMAKE_SYSTEM_PROCESSOR ARM64)
else()
  message(FATAL_ERROR "BISON_ARCH must be x86, x64, or arm64")
endif()

if(DEFINED ENV{WPM_TCC_ROOT} AND NOT "$ENV{WPM_TCC_ROOT}" STREQUAL "")
  file(TO_CMAKE_PATH "$ENV{WPM_TCC_ROOT}" BISON_TCC_ROOT)
else()
  file(TO_CMAKE_PATH "$ENV{ProgramFiles}/TinyCC" _bison_tcc_install_root)
  file(GLOB _bison_tcc_versions LIST_DIRECTORIES TRUE "${_bison_tcc_install_root}/*")
  list(SORT _bison_tcc_versions COMPARE NATURAL ORDER DESCENDING)
  foreach(_candidate IN LISTS _bison_tcc_versions)
    if(EXISTS "${_candidate}/${_bison_tcc_driver}")
      set(BISON_TCC_ROOT "${_candidate}")
      break()
    endif()
  endforeach()
endif()
if(NOT BISON_TCC_ROOT)
  message(FATAL_ERROR "WPM TinyCC was not found; install tinycc or set WPM_TCC_ROOT")
endif()

set(CMAKE_C_COMPILER "${BISON_TCC_ROOT}/${_bison_tcc_driver}"
  CACHE FILEPATH "WPM TinyCC compiler")
set(CMAKE_LINKER "${BISON_TCC_ROOT}/${_bison_tcc_driver}" CACHE FILEPATH "WPM TinyCC linker")
set(CMAKE_C_LINK_EXECUTABLE "${CMAKE_LINKER} -o <TARGET> <OBJECTS>" CACHE STRING "C linker wrapper")


find_program(_bison_powershell powershell.exe REQUIRED)
get_filename_component(_bison_archiver
  "${CMAKE_CURRENT_LIST_DIR}/../TinyCCArchiver.ps1" ABSOLUTE)
string(REPLACE "'" "''" _bison_tcc_literal "${CMAKE_C_COMPILER}")
execute_process(
  COMMAND "${_bison_powershell}" -NoProfile -Command
    "[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('${_bison_tcc_literal}'))"
  OUTPUT_VARIABLE _bison_tcc_base64
  OUTPUT_STRIP_TRAILING_WHITESPACE
  COMMAND_ERROR_IS_FATAL ANY
)
set(CMAKE_AR "${_bison_powershell}" CACHE FILEPATH "PowerShell archiver launcher")
set(CMAKE_C_ARCHIVE_CREATE
  "<CMAKE_AR> -NoProfile -ExecutionPolicy Bypass -File \"${_bison_archiver}\" ${_bison_tcc_base64} rc <TARGET> <OBJECTS>")
set(CMAKE_C_ARCHIVE_APPEND
  "<CMAKE_AR> -NoProfile -ExecutionPolicy Bypass -File \"${_bison_archiver}\" ${_bison_tcc_base64} r <TARGET> <OBJECTS>")
set(CMAKE_C_ARCHIVE_FINISH "")

