param(
    [Parameter(Mandatory)] [string] $TinyCCBase64,
    [Parameter(Mandatory)] [string] $Mode,
    [Parameter(Mandatory)] [string] $Archive,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Objects
)

$tinyCc = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TinyCCBase64))
# Determine architecture based on compiler name
if ($tinyCc -like '*i386-win32-tcc.exe') {
    # 32-bit Windows build – use VS lib.exe for x86
    $lib = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\HostX86\x86\lib.exe'
    & $lib /OUT:$Archive @Objects
    exit $LASTEXITCODE
} elseif ($tinyCc -like '*x86_64-win32-tcc.exe') {
    # 64-bit Windows build – use VS lib.exe for x64
    $lib = 'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\lib.exe'
    & $lib /OUT:$Archive @Objects
    exit $LASTEXITCODE
} else {
    # Fallback to tcc archiver for any other configuration
    & $tinyCc -ar $Mode $Archive @Objects
    exit $LASTEXITCODE
}

