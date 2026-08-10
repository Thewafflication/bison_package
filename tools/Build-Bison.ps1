[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateSet('x86', 'x64', 'arm64')]
    [string] $Architecture,
    [Parameter(Mandatory)] [string] $SourceDirectory,
    [Parameter(Mandatory)] [string] $BuildDirectory,
    [Parameter(Mandatory)] [string] $TinyCcRoot,
    [Parameter(Mandatory)] [string] $WcrtRoot
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path ([IO.Path]::GetFullPath($BuildDirectory)) | Out-Null
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
$bash = Join-Path $gitRoot 'bin/bash.exe'
if (-not (Test-Path -LiteralPath $bash)) {
    throw "Git Bash was not found at $bash"
}

$arguments = @(
    (Join-Path $PSScriptRoot 'build-bison.sh'),
    $repositoryRoot,
    ([IO.Path]::GetFullPath($SourceDirectory)),
    ([IO.Path]::GetFullPath($BuildDirectory)),
    $Architecture,
    ([IO.Path]::GetFullPath($TinyCcRoot)),
    ([IO.Path]::GetFullPath($WcrtRoot))
)
& $bash @arguments
if ($LASTEXITCODE -ne 0) {
    throw "The $Architecture TinyCC/WCRT Bison build failed."
}
