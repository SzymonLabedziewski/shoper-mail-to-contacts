# Terminal colors for the interactive wizard (Windows PowerShell 5.1+).

function Write-Ui {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Title', 'Section', 'Info', 'Muted', 'Ok', 'Warn', 'Err', 'Accent', 'Value')]
        [string]$Kind,
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,
        [switch]$NoNewline
    )
    $color = switch ($Kind) {
        'Title'   { 'Cyan' }
        'Section' { 'Cyan' }
        'Info'    { 'White' }
        'Muted'   { 'White' }
        'Ok'      { 'Green' }
        'Warn'    { 'Yellow' }
        'Err'     { 'Red' }
        'Accent'  { 'Magenta' }
        'Value'   { 'White' }
    }
    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $color -NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor $color
    }
}

function Read-UiHost {
    param(
        [string]$Prompt,
        [string]$Hint = '',
        [ConsoleColor]$PromptColor = [ConsoleColor]::Yellow
    )
    Write-Host ''
    Write-Host $Prompt -ForegroundColor $PromptColor -NoNewline
    if ($Hint -ne '') {
        Write-Host " [$Hint]" -ForegroundColor White -NoNewline
    }
    Write-Host ': ' -ForegroundColor White -NoNewline
    $value = Read-Host
    if ($null -eq $value) { return '' }
    return $value.Trim()
}

function Write-UiFolderDecision {
    param($Infos)
    foreach ($i in @($Infos)) {
        if ($i.include) {
            Write-Host 'SCAN' -ForegroundColor Green -NoNewline
            Write-Host ("  {0}" -f $i.name) -ForegroundColor White -NoNewline
            Write-Host ("  ({0})" -f $i.reason) -ForegroundColor DarkGray
        }
        else {
            Write-Host 'skip' -ForegroundColor DarkGray -NoNewline
            Write-Host ("  {0}" -f $i.name) -ForegroundColor DarkGray -NoNewline
            Write-Host ("  ({0})" -f $i.reason) -ForegroundColor DarkGray
        }
    }
}

function Write-UiFolderCountLine {
    param(
        [string]$Name,
        [string]$CountLabel,
        [int]$OrderCount = -1,
        [string]$Extra = '',
        [ConsoleColor]$CountColor = [ConsoleColor]::Cyan
    )
    Write-Host ("`t{0}: " -f $Name) -ForegroundColor White -NoNewline
    Write-Host $CountLabel -ForegroundColor $CountColor -NoNewline
    if ($OrderCount -ge 0) {
        Write-Host '  (w tym ' -ForegroundColor White -NoNewline
        Write-Host $OrderCount -ForegroundColor Magenta -NoNewline
        Write-Host ' potwierdzeń)' -ForegroundColor White -NoNewline
    }
    if ($Extra -ne '') {
        Write-Host $Extra -ForegroundColor White
    }
    else {
        Write-Host ''
    }
}
