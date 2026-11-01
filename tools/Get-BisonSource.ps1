[CmdletBinding()]
param(
    [string] $Destination = 'out/source/bison-3.8.2'
)

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
$version = '3.8.2'
$archiveName = "bison-$version.tar.xz"
$archive = Join-Path $repositoryRoot "out/downloads/$archiveName"
$sourceRoot = Join-Path $repositoryRoot $Destination
$stamp = Join-Path $sourceRoot '.bison-wcrt-source'
$url = "https://ftp.gnu.org/gnu/bison/$archiveName"
$expectedHash = '9BBA0214CCF7F1079C5D59210045227BCF619519840EBFA80CD3849CFF5A5BF2'
$patch = Join-Path $repositoryRoot 'patches/bison-3.8.2-wcrt.patch'
$patchHash = Get-Sha256Hash $patch
$expectedStamp = "$expectedHash`n$patchHash"

if ((Test-Path -LiteralPath $stamp -PathType Leaf) -and
    (((Get-Content -LiteralPath $stamp) -join "`n") -eq $expectedStamp) -and
    (Select-String -LiteralPath (Join-Path $sourceRoot 'src/output.c') `
        -Pattern 'WCRT 0.9.5 intentionally' -Quiet)) {
    Write-Host "Using prepared Bison source at $sourceRoot"
    return
}

$downloadDirectory = Split-Path -Parent $archive
New-Item -ItemType Directory -Force -Path $downloadDirectory | Out-Null
if (Test-Path -LiteralPath $archive -PathType Leaf) {
    $actualHash = Get-Sha256Hash $archive
    if ($actualHash -ne $expectedHash) {
        throw "Existing Bison archive has SHA-256 $actualHash; expected $expectedHash"
    }
}
else {
    $temporary = "$archive.download"
    try {
        Invoke-WebRequest -UseBasicParsing $url -OutFile $temporary
        $actualHash = Get-Sha256Hash $temporary
        if ($actualHash -ne $expectedHash) {
            throw "Downloaded Bison archive has SHA-256 $actualHash; expected $expectedHash"
        }
        Move-Item -LiteralPath $temporary -Destination $archive
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

$sourceParent = Split-Path -Parent $sourceRoot
$resolvedParent = [IO.Path]::GetFullPath($sourceParent)
$allowedParent = [IO.Path]::GetFullPath((Join-Path $repositoryRoot 'out/source'))
if (-not $resolvedParent.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to prepare Bison outside $allowedParent"
}
if (Test-Path -LiteralPath $sourceRoot) {
    Remove-Item -LiteralPath $sourceRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $sourceParent | Out-Null
& tar.exe -xf $archive -C $sourceParent
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $sourceRoot 'configure'))) {
    throw 'Could not extract the official Bison release archive.'
}

# Compute relative path manually since [IO.Path]::GetRelativePath may not be available
$relativePath = $sourceRoot.Substring($repositoryRoot.Length)
if ($relativePath.StartsWith('\') -or $relativePath.StartsWith('/')) {
    $relativePath = $relativePath.Substring(1)
}
$relativeSource = $relativePath.Replace('\', '/')
& git -C $repositoryRoot apply --check "--directory=$relativeSource" $patch
if ($LASTEXITCODE -ne 0) { throw 'The WCRT patch does not apply to Bison 3.8.2.' }
& git -C $repositoryRoot apply "--directory=$relativeSource" $patch
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the Bison WCRT patch.' }
Set-Content -LiteralPath $stamp -Value @($expectedHash, $patchHash) -Encoding ascii