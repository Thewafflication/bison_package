param(
    [Parameter(Mandatory)] [string] $TinyCCBase64,
    [Parameter(Mandatory)] [string] $Mode,
    [Parameter(Mandatory)] [string] $Archive,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Objects
)

$tinyCc = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TinyCCBase64))
# Use tcc -ar for all architectures, since tcc compiles to ELF-format objects
# and its archiver produces POSIX archives that link.exe can consume.
& $tinyCc -ar $Mode $Archive @Objects
exit $LASTEXITCODE

