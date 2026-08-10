param(
    [Parameter(Mandatory)] [string] $TinyCCBase64,
    [Parameter(Mandatory)] [string] $Mode,
    [Parameter(Mandatory)] [string] $Archive,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Objects
)

$tinyCc = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($TinyCCBase64)
)
& $tinyCc -ar $Mode $Archive @Objects
exit $LASTEXITCODE

