[CmdletBinding()]
param(
    [ValidateSet('x86', 'x64', 'arm64')]
    [string[]] $Architecture
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$cmakeCommand = Get-Command cmake.exe -ErrorAction SilentlyContinue
if ($cmakeCommand) {
    $cmake = $cmakeCommand.Source
}
else {
    $cmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $cmake)) { throw 'CMake was not found.' }
}
$ctest = Join-Path (Split-Path -Parent $cmake) 'ctest.exe'
$ninjaCommand = Get-Command ninja.exe -ErrorAction SilentlyContinue
$ninjaArgument = @()
if (-not $ninjaCommand) {
    $ninja = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'
    if (-not (Test-Path -LiteralPath $ninja)) { throw 'Ninja was not found.' }
    $ninjaArgument = @("-DCMAKE_MAKE_PROGRAM=$ninja")
}
$hostArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
if (-not $Architecture) {
    $Architecture = if ($hostArchitecture -eq 'Arm64') {
        @('x86', 'x64', 'arm64')
    }
    elseif ($hostArchitecture -eq 'X64') {
        @('x86', 'x64')
    }
    else {
        @('x86')
    }
}
if ($Architecture -contains 'arm64' -and $hostArchitecture -ne 'Arm64') {
    throw 'The ARM64 smoke test requires an ARM64 Windows host.'
}

Push-Location $repositoryRoot
try {
    & (Join-Path $PSScriptRoot 'Get-BisonSource.ps1')
    & (Join-Path $PSScriptRoot 'Get-HostTools.ps1')
    foreach ($target in $Architecture) {
        & $cmake --fresh --preset "$target-release" @ninjaArgument
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed for $target" }
        & $cmake --build --preset "build-$target-release"
        if ($LASTEXITCODE -ne 0) { throw "CMake build failed for $target" }
        & $ctest --preset "test-$target-release"
        if ($LASTEXITCODE -ne 0) { throw "CTest failed for $target" }
        & $cmake --install "out/build/$target-release"
        if ($LASTEXITCODE -ne 0) { throw "CMake install failed for $target" }
    }
}
finally {
    Pop-Location
}
