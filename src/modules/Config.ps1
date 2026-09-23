function Get-DefaultConfig {
    $shoper = Get-ShoperImapPreset
    [PSCustomObject]@{
        imap = [PSCustomObject]@{
            host                  = [string]$shoper.Host
            port                  = [int]$shoper.Port
            tls                   = [string]$shoper.Tls
            user                  = ""
            insecureSkipCert      = $false
            parallelFolders       = 3
            markSeen              = $false
            maxMessagesPerFolder  = 0
        }
        self = [PSCustomObject]@{
            emails = @('sklep@example.com')
            phones = @()
            nips   = @()
        }
        folders = [PSCustomObject]@{
            include          = @()
            excludeNameRegex = '(?i)(Sent|Wysłane|Trash|Kosz|Junk|Spam|Drafts|Szkice|Archive|Archiwum|Niechciane|Templates)'
        }
        orders = [PSCustomObject]@{
            enabled  = $true
            adapter  = 'shoper'
        }
        signatures = [PSCustomObject]@{
            enabled            = $true
            useOllama          = $false
            aiConfidenceBelow  = 0.45
        }
        ollama = [PSCustomObject]@{
            url               = 'http://127.0.0.1:11434'
            model             = 'qwen2.5:3b-instruct-q4_K_M'
            recommendedModel  = 'qwen3:4b-instruct-2507'
        }
        output = [PSCustomObject]@{
            dir = './data'
        }
    }
}

function Read-AppConfig {
    param([string]$Path)
    $cfg = Get-DefaultConfig
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $cfg }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($section in @('imap', 'self', 'folders', 'orders', 'signatures', 'ollama', 'output')) {
        if ($raw.PSObject.Properties.Name -contains $section -and $raw.$section) {
            foreach ($p in $raw.$section.PSObject.Properties) {
                if ($cfg.$section.PSObject.Properties.Name -contains $p.Name) {
                    $cfg.$section.($p.Name) = $p.Value
                }
            }
        }
    }
    # PS 5.1: pojedynczy element w JSON array bywa stringiem — zawsze tablica stringów
    $cfg.self.emails = Get-NormalizedEmailList $cfg.self.emails
    $cfg.self.phones = ConvertTo-FlatStringArray $cfg.self.phones
    $cfg.self.nips = ConvertTo-FlatStringArray $cfg.self.nips
    return $cfg
}

function Get-ImapPassword {
    param([string]$User)
    if ($env:IMAP_PASSWORD) { return $env:IMAP_PASSWORD }
    Write-Host ''
    Write-Host "Hasło IMAP dla $User" -ForegroundColor Yellow -NoNewline
    Write-Host ': ' -ForegroundColor White -NoNewline
    $sec = Read-Host -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function ConvertTo-JsonText {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
    return '"' + $escaped + '"'
}

function ConvertTo-JsonTextArray {
    param($Items)
    $vals = @()
    foreach ($x in @($Items)) {
        if ($null -eq $x) { continue }
        $vals += (ConvertTo-JsonText ([string]$x))
    }
    return '[' + ($vals -join ', ') + ']'
}

function ConvertTo-JsonBool {
    param([bool]$Value)
    if ($Value) { 'true' } else { 'false' }
}

function New-AppConfigFromAnswers {
    param(
        [Parameter(Mandatory = $true)][string]$Email
    )
    $addr = $Email.Trim()
    if ($addr -notmatch '@') { throw 'Podaj poprawny adres e-mail (musi zawierać @).' }
    $cfg = Get-DefaultConfig
    $cfg.imap.user = $addr
    $cfg.self.emails = Get-NormalizedEmailList @($addr)
    $cfg.orders.adapter = 'shoper'
    $cfg.orders.enabled = $true
    return $cfg
}

function Save-AppConfig {
    param($Config, [string]$Path)
    if (-not $Path) { throw 'Save-AppConfig: brak ścieżki.' }
    $dir = [IO.Path]::GetDirectoryName($Path)
    if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    $imap = $Config.imap
    $self = $Config.self
    $folders = $Config.folders
    $orders = $Config.orders
    $sig = $Config.signatures
    $ollama = $Config.ollama
    $output = $Config.output
    $json = @"
{
  "imap": {
    "host": $(ConvertTo-JsonText ([string]$imap.host)),
    "port": $([int]$imap.port),
    "tls": $(ConvertTo-JsonText ([string]$imap.tls)),
    "user": $(ConvertTo-JsonText ([string]$imap.user)),
    "insecureSkipCert": $(ConvertTo-JsonBool ([bool]$imap.insecureSkipCert)),
    "parallelFolders": $([int]$imap.parallelFolders),
    "markSeen": $(ConvertTo-JsonBool ([bool]$imap.markSeen)),
    "maxMessagesPerFolder": $([int]$imap.maxMessagesPerFolder)
  },
  "self": {
    "emails": $(ConvertTo-JsonTextArray @($self.emails)),
    "phones": $(ConvertTo-JsonTextArray @($self.phones)),
    "nips": $(ConvertTo-JsonTextArray @($self.nips))
  },
  "folders": {
    "include": $(ConvertTo-JsonTextArray @($folders.include)),
    "excludeNameRegex": $(ConvertTo-JsonText ([string]$folders.excludeNameRegex))
  },
  "orders": {
    "enabled": $(ConvertTo-JsonBool ([bool]$orders.enabled)),
    "adapter": $(ConvertTo-JsonText ([string]$orders.adapter))
  },
  "signatures": {
    "enabled": $(ConvertTo-JsonBool ([bool]$sig.enabled)),
    "useOllama": $(ConvertTo-JsonBool ([bool]$sig.useOllama)),
    "aiConfidenceBelow": $([double]$sig.aiConfidenceBelow)
  },
  "ollama": {
    "url": $(ConvertTo-JsonText ([string]$ollama.url)),
    "model": $(ConvertTo-JsonText ([string]$ollama.model)),
    "recommendedModel": $(ConvertTo-JsonText ([string]$ollama.recommendedModel))
  },
  "output": {
    "dir": $(ConvertTo-JsonText ([string]$output.dir))
  }
}
"@
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText($Path, $json.Trim() + "`n", $utf8)
}
