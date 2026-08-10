[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Bison,
    [Parameter(Mandatory)] [string] $DataDirectory,
    [Parameter(Mandatory)] [string] $M4Directory,
    [Parameter(Mandatory)] [string] $TestDirectory
)

$ErrorActionPreference = 'Stop'
$testRoot = [IO.Path]::GetFullPath($TestDirectory)
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$grammar = Join-Path $testRoot 'smoke.y'
$output = Join-Path $testRoot 'smoke.c'
@'
%{
#include <stdio.h>
int yylex(void) { return 0; }
void yyerror(const char *message) { (void)message; }
%}
%token NUMBER
%%
input: %empty | input NUMBER ;
%%
int main(void) { return yyparse(); }
'@ | Set-Content -LiteralPath $grammar -Encoding ascii

$env:PATH = ([IO.Path]::GetFullPath($M4Directory)) + ';' + $env:PATH
$env:M4 = 'm4.exe'
$env:BISON_PKGDATADIR = [IO.Path]::GetFullPath($DataDirectory)
$version = & ([IO.Path]::GetFullPath($Bison)) --version 2>&1
if ($LASTEXITCODE -ne 0 -or $version[0] -notmatch 'bison \(GNU Bison\) 3\.8\.2') {
    throw 'The native Bison executable did not report the expected version.'
}
& ([IO.Path]::GetFullPath($Bison)) -Wall -o $output $grammar
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw 'Bison did not generate the smoke-test parser.'
}
if (-not (Select-String -LiteralPath $output -Pattern 'yyparse' -Quiet)) {
    throw 'The generated parser does not contain yyparse.'
}

