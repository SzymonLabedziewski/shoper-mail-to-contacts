#Requires -Version 5.1
<#
.SYNOPSIS
  Książka adresowa z poczty Shoper/Shoparena (IMAP + MailKit).

.EXAMPLE
  powershell -File .\Uruchom.ps1
  .\src\MailToContacts.ps1 setup
  .\src\MailToContacts.ps1 run -Folders INBOX -MaxMessages 200
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('demo', 'init', 'discover', 'run', 'selftest', 'install-mailkit', 'setup', 'help')]
    [string]$Command = 'help',

    [string]$Email = '',
    [string]$ConfigPath = '',
    [string]$Samples = '',
    [string]$Out = '',
    [string]$FetchedDir = '',
    [string[]]$Folders = @(),
    [int]$MaxMessages = -1,
    [switch]$NoProgress,
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'
# PS 5.1 + polskie znaki w konsoli (pliki .ps1 = UTF-8 z BOM; tu tylko OutputEncoding).
try {
    if ($Host.Name -eq 'ConsoleHost') {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $OutputEncoding = [Console]::OutputEncoding
    }
}
catch { }
$RepoRoot = Split-Path -Parent $PSScriptRoot
$modDir = Join-Path $PSScriptRoot 'modules'
@(
    'Ui.ps1', 'PlIds.ps1', 'TextUtil.ps1', 'Providers.ps1', 'FolderPolicy.ps1',
    'Orders.ps1', 'Signatures.ps1', 'Merge.ps1', 'Export.ps1',
    'Config.ps1', 'Ollama.ps1', 'ImapClient.ps1', 'Pipeline.ps1', 'Setup.ps1'
) | ForEach-Object { . (Join-Path $modDir $_) }

if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot 'config.json' }
if (-not $Samples) { $Samples = Join-Path $RepoRoot 'samples\fetched' }
if (-not $Out) { $Out = Join-Path $RepoRoot 'samples\generated' }

switch ($Command) {
    'help' {
        @'
MailToContacts — książka adresowa z poczty Shoper/Shoparena (PowerShell + MailKit).

  setup                kreator: SelfTest → e-mail → stopy → Ollama → foldery/limit → run
  selftest             testy bez sieci
  demo                 pipeline na samples/fetched (zamówienia + stopy)
  init                 zapisz config.json (host Shoper + e-mail, bez hasła)
  install-mailkit      MailKit 4.17 → lib/mailkit
  discover             LIST folderów SCAN/skip
  run                  pobranie + VCF
    -Folders INBOX
    -MaxMessages 200
    -Interactive
    -NoProgress

Najprościej:  powershell -File .\Uruchom.ps1
Warstwy: potwierdzenia → stopy (domyślnie ON) → Ollama (domyślnie OFF).
IMAP: s.mail.dcsaas.net:143 STARTTLS. Hasło: IMAP_PASSWORD albo prompt (nie w config.json).
Foldery: bez domyślnego — numery / * / nazwa.
'@ | Write-Host
    }
    'selftest' {
        & (Join-Path $RepoRoot 'tests\SelfTest.ps1')
    }
    'demo' {
        $cfg = Get-DefaultConfig
        $book = Invoke-OfflinePipeline -FetchedDir $Samples -OutDir $Out -Config $cfg
        Write-Host "contacts=$($book.contactCount) -> $Out"
    }
    'init' {
        Invoke-ConfigWizard -RepoRoot $RepoRoot -ConfigPath $ConfigPath -Email $Email | Out-Null
    }
    'setup' {
        Invoke-SetupWizard -RepoRoot $RepoRoot -ConfigPath $ConfigPath -Email $Email
    }
    'install-mailkit' {
        Install-MailKitLibs $RepoRoot
    }
    'discover' {
        $cfg = Read-AppConfig $ConfigPath
        if (-not $cfg.imap.user -or -not $cfg.imap.host) { throw 'Brak imap.user / imap.host — uruchom setup albo init.' }
        Ensure-MailKit $RepoRoot
        $pass = Get-ImapPassword $cfg.imap.user
        $infos = Invoke-ImapDiscover -Config $cfg -Password $pass -RepoRoot $RepoRoot
        Format-ImapFolderDecision $infos
    }
    'run' {
        $cfg = Read-AppConfig $ConfigPath
        if (-not $cfg.imap.user -or -not $cfg.imap.host) { throw 'Brak imap.user / imap.host — uruchom setup albo init.' }
        Ensure-MailKit $RepoRoot
        $pass = Get-ImapPassword $cfg.imap.user
        $useFolders = ConvertTo-FlatStringArray $Folders
        $useMax = $MaxMessages
        $ask = $Interactive -or (($useFolders.Count -eq 0) -and ($useMax -lt 0) -and (Test-IsInteractiveConsole))
        if ($ask) {
            Write-Ui Section 'LIST folderów IMAP…'
            $infos = Invoke-ImapDiscover -Config $cfg -Password $pass -RepoRoot $RepoRoot
            Write-UiFolderDecision $infos
            $plan = Invoke-FetchPlanWizard -Config $cfg -Password $pass -RepoRoot $RepoRoot -FolderInfos $infos
            $useFolders = ConvertTo-FlatStringArray $plan.Folders
            $useMax = [int]$plan.MaxMessagesPerFolder
        }
        elseif ($useMax -lt 0) {
            $useMax = [int]$cfg.imap.maxMessagesPerFolder
        }
        $show = -not $NoProgress
        $result = Invoke-ImapLiveRun -Config $cfg -Password $pass -RepoRoot $RepoRoot `
            -Folders $useFolders -MaxMessagesPerFolder $useMax -ShowProgress:$show
        Write-Host ''
        Write-Host 'contacts=' -ForegroundColor White -NoNewline
        Write-Host $result.Book.contactCount -ForegroundColor Green -NoNewline
        Write-Host ' -> ' -ForegroundColor White -NoNewline
        Write-Host $result.RunDir -ForegroundColor White
    }
}
