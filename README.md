# GNU Bison for WPM

This project builds GNU Bison 3.8.2 for Windows with CMake, the WPM TinyCC
toolchain, and WCRT, then stages a relocatable install tree and WPM package.
The Bison executable is statically linked to WCRT. GNU M4 remains Bison's
external skeleton processor and is included in the package as a pinned host
tool.

## Prerequisites

- CMake 3.24 or newer and Ninja
- Git for Windows (the upstream configure step uses Git Bash)
- WPM TinyCC 0.9.28 or newer
- WPM WCRT 0.9.5 or newer
- WPM itself when building the final package

The repository path must not contain spaces because Bison 3.8.2's Autotools
makefiles do not reliably support them.

## Build

The convenience script acquires hash-pinned official sources and host tools,
then configures, builds, tests, and installs every architecture supported by
the current host:

```powershell
.\tools\Build-Native.ps1 -Architecture x64
```

The equivalent individual CMake commands are:

```powershell
cmake --preset x64-release
cmake --build --preset build-x64-release
ctest --preset test-x64-release
cmake --install out/build/x64-release
```

Replace `x64` with `x86` or `arm64` as needed. `WPM_TCC_ROOT` and
`WPM_WCRT_ROOT` may select nonstandard toolchain installations. The first
build is intentionally slower because Bison's complete gnulib configuration
is evaluated for the target CRT.

## Package

After building a preset, create its WPM archive with:

```powershell
cmake --build out/build/x64-release --target wpm-package
```

The archive is written to `out/packages`. Its installer places the payload in
`%ProgramFiles%\Bison\<version>`, defines `BISON_HOME` and
`BISON_PKGDATADIR`, and adds `%BISON_HOME%\bin` to the machine `PATH`.

## Port boundary

The official Bison release archive is left conceptually upstream. The small
patch in `patches/` replaces its bidirectional POSIX pipe to M4 with WCRT-safe
temporary files, and `compat/` supplies the narrow Win32 descriptor and
filesystem bridge required by gnulib. Generated gnulib wrapper headers are
adapted only inside the build tree.

