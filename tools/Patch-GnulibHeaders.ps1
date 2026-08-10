[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BuildDirectory,
    [Parameter(Mandatory)] [string] $WcrtRoot
)

$ErrorActionPreference = 'Stop'
$buildRoot = [IO.Path]::GetFullPath($BuildDirectory)
$lib = Join-Path $buildRoot 'lib'
$wcrtInclude = Join-Path ([IO.Path]::GetFullPath($WcrtRoot)) 'include'
$systemHeaders = Join-Path $lib 'wcrt-system'

if (-not (Test-Path -LiteralPath (Join-Path $lib 'config.h'))) {
    throw "Bison has not been configured in $buildRoot"
}
if (-not (Test-Path -LiteralPath (Join-Path $lib 'errno.h'))) {
    throw 'The generated gnulib headers are missing.'
}
if (Test-Path -LiteralPath $systemHeaders) {
    Remove-Item -LiteralPath $systemHeaders -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $systemHeaders | Out-Null
Copy-Item -Path (Join-Path $wcrtInclude '*') -Destination $systemHeaders -Recurse -Force

function Update-TextFile {
    param([string] $Path, [scriptblock] $Transform)
    $text = [IO.File]::ReadAllText($Path)
    $updated = & $Transform $text
    [IO.File]::WriteAllText($Path, $updated, [Text.UTF8Encoding]::new($false))
}

$providedHeaders = @(
    'errno.h', 'limits.h', 'math.h', 'signal.h', 'stddef.h', 'stdint.h',
    'stdio.h', 'stdlib.h', 'string.h', 'sys/stat.h', 'time.h'
)
foreach ($header in $providedHeaders) {
    $path = Join-Path $lib $header
    $escaped = [regex]::Escape($header.Replace('\', '/'))
    Update-TextFile $path {
        param($text)
        [regex]::Replace(
            $text,
            "(?m)^(\s*#\s*)include_next\s*<$escaped>\s*$",
            "`${1}include <wcrt-system/$($header.Replace('\', '/'))>"
        )
    }
}

$stdio = Join-Path $lib 'stdio.h'
Update-TextFile $stdio {
    param($text)
    $text.Replace(
        '#include <wcrt-system/stdio.h>',
        "#include <wcrt-system/stdio.h>`nFILE *_fdopen (int descriptor, const char *mode);`nint _getmaxstdio (void);`nint _setmaxstdio (int count);"
    )
}
$stdlib = Join-Path $lib 'stdlib.h'
Update-TextFile $stdlib {
    param($text)
    $text.Replace(
        '#include <wcrt-system/stdlib.h>',
        "#include <wcrt-system/stdlib.h>`nconst char *getprogname (void);`nextern char **environ;"
    )
}
$math = Join-Path $lib 'math.h'
Update-TextFile $math {
    param($text)
    $text.Replace(
        '#include <wcrt-system/math.h>',
        "#include <wcrt-system/math.h>`nint signbit (double value);"
    )
}

foreach ($header in @('unistd.h', 'sys/time.h', 'wchar.h', 'wctype.h')) {
    $path = Join-Path $lib $header
    if (Test-Path -LiteralPath $path) {
        Update-TextFile $path {
            param($text)
            [regex]::Replace(
                $text,
                '(?m)^\s*#\s*include_next\s*<[^>]+>\s*$',
                '/* WCRT has no corresponding system header. */'
            )
        }
    }
}

$unistd = Join-Path $lib 'unistd.h'
Update-TextFile $unistd {
    param($text)
    $text.Replace(
        "#define _GL_UNISTD_H`n",
        "#define _GL_UNISTD_H`nvoid _exit (int status);`n"
    )
}

$wctype = Join-Path $lib 'wctype.h'
Update-TextFile $wctype {
    param($text)
    $text = $text.Replace('# if defined __MINGW32__ && !0', '# if 0')
    $text = $text.Replace(
        "#if !0`n# if !GNULIB_defined_wctype_t`ntypedef void * wctype_t;`n#  define GNULIB_defined_wctype_t 1`n# endif`n#endif",
        "#if !0`n# if !GNULIB_defined_wctype_t`n#  ifndef _WCTYPE_T_DEFINED`n#   define _WCTYPE_T_DEFINED`ntypedef wchar_t wctype_t;`n#  endif`n#  define GNULIB_defined_wctype_t 1`n# endif`n#endif"
    )
    $text
}

$errno = Join-Path $systemHeaders 'errno.h'
$errnoConstants = @'

/* POSIX-compatible values used by Bison's gnulib portability layer. */
#define EPERM 1
#define ESRCH 3
#define EINTR 4
#define EIO 5
#define ENXIO 6
#define E2BIG 7
#define ENOEXEC 8
#define EBADF 9
#define ECHILD 10
#define EAGAIN 11
#define ENOMEM 12
#define EFAULT 14
#define EBUSY 16
#define EEXIST 17
#define EXDEV 18
#define ENODEV 19
#define ENOTDIR 20
#define EISDIR 21
#define ENFILE 23
#define ENOTTY 25
#define EFBIG 27
#define ENOSPC 28
#define ESPIPE 29
#define EROFS 30
#define EMLINK 31
#define EPIPE 32
#define EDEADLK 36
#define ENAMETOOLONG 38
#define ENOSYS 40
#define ENOTEMPTY 41
#define EILSEQ 42
'@
Update-TextFile $errno {
    param($text)
    $text.Replace(
        '/** @brief Invalid argument reported by Microsoft compatibility interfaces. */',
        $errnoConstants + "`n/** @brief Invalid argument reported by Microsoft compatibility interfaces. */"
    )
}

$stat = Join-Path $systemHeaders 'sys/stat.h'
$statDefinitions = @'
/* gnulib selects MinGW's 64-bit spelling on native Windows. */
#define _stati64 _stat64

#define _S_IFIFO 0x1000 /**< FIFO file type. */
#define _S_IFCHR 0x2000 /**< Character-device file type. */
#define _S_IFMT 0xF000

#define S_IFDIR _S_IFDIR
#define S_IFREG _S_IFREG
#define S_IFMT _S_IFMT
#define S_IREAD _S_IREAD
#define S_IWRITE _S_IWRITE
#define S_IEXEC _S_IEXEC

'@
Update-TextFile $stat {
    param($text)
    $text.Replace(
        '#define _S_IFDIR 0x4000 /**< Directory file type. */',
        $statDefinitions + '#define _S_IFDIR 0x4000 /**< Directory file type. */'
    )
}

$config = Join-Path $lib 'config.h'
Update-TextFile $config {
    param($text)
    [regex]::Replace($text, '(?m)^#define M4 ".*"$', '#define M4 "m4.exe"')
}
Set-Content -LiteralPath (Join-Path $buildRoot '.wcrt-headers') -Value 'patched' -Encoding ascii
