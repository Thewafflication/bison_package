[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('x86', 'x64', 'arm64')]
    [string] $Architecture,
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $InstallRoot,
    [string] $PackageRoot = 'out/packages',
    [string] $Wpm = 'wpm.exe',
    [string] $SigningKey
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$packageVersion = $Version -replace '^v', ''
if ($packageVersion -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$') {
    throw "Bison package version is not semantic: $Version"
}

$payload = [IO.Path]::GetFullPath($InstallRoot)
foreach ($required in @(
        'bin/bison.exe', 'bin/m4.exe', 'bin/msys-2.0.dll',
        'share/bison/skeletons/bison.m4', 'share/bison/m4sugar/m4sugar.m4')) {
    if (-not (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf)) {
        throw "The install tree is missing $required"
    }
}

$staging = Join-Path $repositoryRoot "out/wpm-staging/$Architecture"
$packageOutput = Join-Path $repositoryRoot $PackageRoot
$allowedStaging = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'out/wpm-staging'))
if (-not ([IO.Path]::GetFullPath($staging)).StartsWith(
        $allowedStaging, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The WPM staging directory is outside the repository output tree.'
}
if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path `
    $staging, (Join-Path $staging '.wpm'), $packageOutput | Out-Null
Copy-Item -Path (Join-Path $payload '*') -Destination $staging -Recurse

$savedErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
$gitRevision = & git -C $repositoryRoot rev-parse --short=8 HEAD 2>$null
$gitExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorPreference
$gitHash = if ($gitExitCode -eq 0 -and $gitRevision) {
    $gitRevision.Trim()
}
else {
    'uncommitted'
}
$metadata = @(
    'name=bison'
    "version=$packageVersion"
    "arch=$Architecture"
    'debug=false'
    'description=GNU Bison built for Windows with TinyCC and WCRT'
    'maintainer=Jordan Waughtal'
    'homepage=https://www.gnu.org/software/bison/'
    'license=GPL-3.0-or-later'
    'source-version=3.8.2'
    "source-revision=$gitHash"
)
Set-Content -LiteralPath (Join-Path $staging '.wpm/package.txt') `
    -Value $metadata -Encoding ascii

$installDirectory = "%ProgramFiles%\Bison\$packageVersion"
$installScript = @(
    '@echo off'
    'setlocal EnableDelayedExpansion'
    ('set "BISON_DEST={0}"' -f $installDirectory)
    'set "BISON_ENV=HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
    'if not exist "%BISON_DEST%" mkdir "%BISON_DEST%" || exit /b 1'
    'xcopy "%~dp0..\*" "%BISON_DEST%\" /E /I /Q /Y >nul || exit /b 1'
    'if exist "%BISON_DEST%\.wpm" rmdir /S /Q "%BISON_DEST%\.wpm"'
    'reg add "%BISON_ENV%" /v BISON_HOME /t REG_EXPAND_SZ /d "%BISON_DEST%" /f >nul || exit /b 1'
    'reg add "%BISON_ENV%" /v BISON_PKGDATADIR /t REG_EXPAND_SZ /d "%%BISON_HOME%%\share\bison" /f >nul || exit /b 1'
    'set "BISON_PATH="'
    'for /f "tokens=1,2,*" %%A in (''reg query "%BISON_ENV%" /v Path 2^>nul ^| find /I "Path"'') do set "BISON_PATH=%%C"'
    'echo;!BISON_PATH!;| findstr /I /L /C:";%%BISON_HOME%%\bin;" >nul'
    'if errorlevel 1 set "BISON_PATH=!BISON_PATH!;%%BISON_HOME%%\bin"'
    'reg add "%BISON_ENV%" /v Path /t REG_EXPAND_SZ /d "!BISON_PATH!" /f >nul || exit /b 1'
    'exit /b 0'
)
$removeScript = @(
    '@echo off'
    'setlocal EnableDelayedExpansion'
    ('set "BISON_DEST={0}"' -f $installDirectory)
    'set "BISON_ENV=HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
    'if exist "%BISON_DEST%" rmdir /S /Q "%BISON_DEST%" || exit /b 1'
    'set "BISON_CURRENT="'
    'for /f "tokens=2,*" %%A in (''reg query "%BISON_ENV%" /v BISON_HOME 2^>nul'') do set "BISON_CURRENT=%%B"'
    'if /I not "%BISON_CURRENT%"=="%BISON_DEST%" exit /b 0'
    'set "BISON_PATH="'
    'for /f "tokens=1,2,*" %%A in (''reg query "%BISON_ENV%" /v Path 2^>nul ^| find /I "Path"'') do set "BISON_PATH=%%C"'
    'set "BISON_PATH=!BISON_PATH:;%%BISON_HOME%%\bin=!"'
    'set "BISON_PATH=!BISON_PATH:%%BISON_HOME%%\bin;=!"'
    'set "BISON_PATH=!BISON_PATH:%%BISON_HOME%%\bin=!"'
    'reg add "%BISON_ENV%" /v Path /t REG_EXPAND_SZ /d "!BISON_PATH!" /f >nul'
    'reg delete "%BISON_ENV%" /v BISON_HOME /f >nul 2>&1'
    'reg delete "%BISON_ENV%" /v BISON_PKGDATADIR /f >nul 2>&1'
    'exit /b 0'
)
Set-Content -LiteralPath (Join-Path $staging '.wpm/install.cmd') `
    -Value $installScript -Encoding ascii
Set-Content -LiteralPath (Join-Path $staging '.wpm/remove.cmd') `
    -Value $removeScript -Encoding ascii

$arguments = @('build', $staging, $packageOutput)
if (-not [string]::IsNullOrWhiteSpace($SigningKey)) {
    $arguments += @('--sign', (Resolve-Path -LiteralPath $SigningKey).Path)
}
& $Wpm @arguments
if ($LASTEXITCODE -ne 0) { throw 'WPM failed to create the Bison package.' }

$package = @(Get-ChildItem -LiteralPath $packageOutput `
    -Filter "bison-$Architecture-$packageVersion.zip" -File)
if ($package.Count -ne 1) {
    throw "Expected one Bison WPM package for $Architecture $packageVersion."
}
$package[0].FullName
