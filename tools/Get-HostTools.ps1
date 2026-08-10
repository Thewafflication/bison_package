[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
function Get-Sha256Hash {
    param([Parameter(Mandatory)] [string] $Path)
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputRoot = Join-Path $repositoryRoot 'out/host-tools'
$downloadRoot = Join-Path $repositoryRoot 'out/downloads'
$stamp = Join-Path $outputRoot '.prepared'

if (Test-Path -LiteralPath $stamp -PathType Leaf) {
    Write-Host "Using prepared Bison host tools at $outputRoot"
    return
}

$packages = @(
    @{
        Name = 'm4'
        Archive = 'm4-1.4.19-2-x86_64.pkg.tar.zst'
        Hash = '4A1D296571AFA7B8837FD5E227E16C9CB7E26C0F31F03B364E11C1AE8EE2A913'
    },
    @{
        Name = 'make'
        Archive = 'make-4.4.1-2-x86_64.pkg.tar.zst'
        Hash = '2408AF61717DAE87B00C855B132769A125C708907FC94A46BB16DAE076113E5C'
    }
)

$git = Get-Command git.exe -ErrorAction Stop
$gitRoot = $null
$candidate = Split-Path -Parent $git.Source
while ($candidate) {
    if ((Test-Path -LiteralPath (Join-Path $candidate 'bin/bash.exe')) -and
        (Test-Path -LiteralPath (Join-Path $candidate 'usr/bin/cygpath.exe'))) {
        $gitRoot = $candidate
        break
    }
    $parent = Split-Path -Parent $candidate
    if ($parent -eq $candidate) { break }
    $candidate = $parent
}
if (-not $gitRoot) { throw 'Could not locate the Git for Windows installation root.' }
$gitUsrBin = Join-Path $gitRoot 'usr/bin'
$runtimeLibraries = @('msys-2.0.dll', 'msys-intl-8.dll', 'msys-iconv-2.dll')
foreach ($library in $runtimeLibraries) {
    if (-not (Test-Path -LiteralPath (Join-Path $gitUsrBin $library))) {
        throw "Git for Windows does not provide required M4 runtime library $library"
    }
}

New-Item -ItemType Directory -Force -Path $downloadRoot, $outputRoot | Out-Null
foreach ($package in $packages) {
    $archive = Join-Path $downloadRoot $package.Archive
    $url = "https://repo.msys2.org/msys/x86_64/$($package.Archive)"
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
        $temporary = "$archive.download"
        try {
            Invoke-WebRequest -UseBasicParsing $url -OutFile $temporary
            Move-Item -LiteralPath $temporary -Destination $archive
        }
        finally {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
    $actualHash = Get-Sha256Hash $archive
    if ($actualHash -ne $package.Hash) {
        throw "$($package.Archive) has SHA-256 $actualHash; expected $($package.Hash)"
    }
    $destination = Join-Path $outputRoot $package.Name
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    & tar.exe -xf $archive -C $destination
    if ($LASTEXITCODE -ne 0) { throw "Could not extract $($package.Archive)" }
}

$runtimeBin = Join-Path $outputRoot 'runtime/bin'
New-Item -ItemType Directory -Force -Path $runtimeBin | Out-Null
Copy-Item -LiteralPath (Join-Path $outputRoot 'm4/usr/bin/m4.exe') -Destination $runtimeBin -Force
foreach ($library in $runtimeLibraries) {
    Copy-Item -LiteralPath (Join-Path $gitUsrBin $library) -Destination $runtimeBin -Force
}
& (Join-Path $runtimeBin 'm4.exe') --version | Select-Object -First 1
if ($LASTEXITCODE -ne 0) { throw 'The prepared GNU M4 runtime does not start.' }
Set-Content -LiteralPath $stamp -Value 'm4 1.4.19; make 4.4.1' -Encoding ascii
