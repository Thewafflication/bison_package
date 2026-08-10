#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "usage: build-bison.sh REPOSITORY SOURCE BUILD ARCH TCC_ROOT WCRT_ROOT" >&2
  exit 2
fi

cygpath=/usr/bin/cygpath.exe
repository=$($cygpath -m "$1")
source_root=$($cygpath -m "$2")
build_root=$($cygpath -m "$3")
architecture=$4
tcc_root=$($cygpath -ms "$5")
wcrt_root=$($cygpath -ms "$6")

case "$architecture" in
  x86)
    compiler=i386-win32-tcc.exe
    host=i686-w64-mingw32
    wcrt_arch=x86
    compiler_runtime=i386-win32-libtcc1.a
    ;;
  x64)
    compiler=x86_64-win32-tcc.exe
    host=x86_64-w64-mingw32
    wcrt_arch=x64
    compiler_runtime=x86_64-win32-libtcc1.a
    ;;
  arm64)
    compiler=arm64-win32-tcc.exe
    host=aarch64-w64-mingw32
    wcrt_arch=arm64
    compiler_runtime=arm64-win32-libtcc1.a
    ;;
  *)
    echo "unsupported architecture: $architecture" >&2
    exit 2
    ;;
esac

cc="$tcc_root/$compiler"
wcrt_include="$wcrt_root/include"
wcrt_lib="$wcrt_root/$wcrt_arch/lib"
tcc_lib="$tcc_root/lib"
make_root="$repository/out/host-tools/make/usr/bin"
m4_root="$repository/out/host-tools/m4/usr/bin"
make="$make_root/make.exe"

export PATH="/usr/bin:$PATH"

if [[ ! -f "$build_root/Makefile" ]]; then
  (
    cd "$build_root"
    CC="$cc" \
    LD="$cc" \
    AR="$cc -ar" \
    RANLIB=: \
    M4="$m4_root/m4.exe" \
    CPPFLAGS="-I$wcrt_include" \
    CFLAGS="-std=c99 -O2" \
    LDFLAGS="-nostdlib -Wl,-nostdlib" \
    LIBS="$wcrt_lib/wcrt-startup-console.o $wcrt_lib/libwcrt.a $tcc_lib/$compiler_runtime $tcc_lib/kernel32.def" \
      "$source_root/configure" \
        --build=x86_64-pc-mingw64 \
        --host="$host" \
        --disable-dependency-tracking \
        --disable-nls \
        --disable-rpath \
        --disable-yacc
  )
fi

(
  cd "$build_root"
  generated_rule=$'.SECONDEXPANSION:\nwcrt-generated: $$(BUILT_SOURCES)'
  "$make" --eval="$generated_rule" wcrt-generated
)

powershell_script=$($cygpath -w "$repository/tools/Patch-GnulibHeaders.ps1")
build_windows=$($cygpath -w "$build_root")
wcrt_windows=$($cygpath -w "$wcrt_root")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$powershell_script" \
  -BuildDirectory "$build_windows" -WcrtRoot "$wcrt_windows"

repository_mixed=$($cygpath -m "$repository")
source_mixed=$($cygpath -m "$source_root")
build_mixed=$($cygpath -m "$build_root")
common_defines="-DBISON_WCRT=1 -D__MINGW32__=1 -D_WIN32_WINNT=0x0501 -D_WIN32_WINNT_VISTA=0x0600 -D_WIN32_WINNT_WIN8=0x0602 -DHAVE_GETPROGNAME=1"
common_cppflags="$common_defines -I$repository_mixed/compat -I$wcrt_include"

"$cc" -std=c99 -O2 $common_defines \
  -I"$build_mixed/lib/wcrt-system" -I"$build_mixed/lib" -I"$source_mixed/lib" \
  -I"$repository_mixed/compat" -I"$wcrt_include" \
  -c "$repository_mixed/compat/wcrt_compat.c" \
  -o "$build_mixed/wcrt_compat.o"

jobs=${NUMBER_OF_PROCESSORS:-4}
(
  cd "$build_root"
  "$make" -j"$jobs" \
    CPPFLAGS="$common_cppflags" \
    LIBS="$build_mixed/wcrt_compat.o $wcrt_lib/wcrt-startup-console.o $wcrt_lib/libwcrt.a $tcc_lib/$compiler_runtime $tcc_lib/kernel32.def" \
    src/bison.exe
)
