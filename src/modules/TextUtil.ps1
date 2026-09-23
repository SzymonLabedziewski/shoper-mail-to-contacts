# Shared text helpers. Quote-stripping MUST run before signature extraction.

$script:EmailRx = [regex]'(?i)\b([a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,})\b'
$script:TrackingEmail = [regex]'(?i)clicks\.|trackingservice|token=|unsubscribe'

function ConvertFrom-HtmlToPlain {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return "" }
    $t = [regex]::Replace($Html, '(?is)<(script|style)[^>]*>.*?</\1>', ' ')
    $t = [regex]::Replace($t, '(?i)<br\s*/?>', "`n")
    $t = [regex]::Replace($t, '(?i)</\s*(p|div|tr|li|h[1-6])\s*>', "`n")
    $t = [regex]::Replace($t, '<[^>]+>', ' ')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = $t.Replace([char]0x00A0, ' ')
    $lines = foreach ($line in ($t -split "`n")) { ($line -replace '\s+', ' ').Trim() }
    return (($lines | Where-Object { $_ }) -join "`n")
}

function Test-LooksLikeHtml {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return [bool]($Text -match '(?i)<\s*/?\s*(div|p|br|html|body)\b|&nbsp;')
}

function ConvertTo-NormalizedEmail {
    param(
        [string]$Email,
        [string[]]$SelfEmails = @()
    )
    if ([string]::IsNullOrWhiteSpace($Email)) { return "" }
    $raw = [regex]::Replace($Email.Trim(), '(?i)^mailto:\s*', '')
    $m = [regex]::Match($raw, '([^<\s]+@[^>\s]+)')
    $e = if ($m.Success) { $m.Groups[1].Value } else { $raw }
    $e = $e.Trim('.', ',', ';').ToLowerInvariant()
    if ($e -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return "" }
    if ($script:TrackingEmail.IsMatch($e)) { return "" }
    $self = @($SelfEmails | ForEach-Object { $_.ToLowerInvariant() })
    if ($self -contains $e) { return "" }
    return $e
}

function Get-EmailsInText {
    param(
        [string]$Text,
        [string[]]$SelfEmails = @()
    )
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($m in $script:EmailRx.Matches($Text)) {
        $e = ConvertTo-NormalizedEmail $m.Groups[1].Value $SelfEmails
        if ($e -and -not $out.Contains($e)) { $out.Add($e) }
    }
    return @($out)
}

function ConvertTo-NormalizedPhone {
    param(
        [string]$Phone,
        [string[]]$SelfPhones = @()
    )
    if ([string]::IsNullOrWhiteSpace($Phone)) { return "" }
    $d = [regex]::Replace($Phone, '[^\d+]', '')
    if ($d.StartsWith('+48')) { $d = $d.Substring(3) }
    elseif ($d.StartsWith('0048')) { $d = $d.Substring(4) }
    elseif ($d.StartsWith('48') -and ((Get-DigitsOnly $d).Length -ge 11)) { $d = $d.Substring(2) }
    $digits = Get-DigitsOnly $d
    if ($digits.Length -lt 9 -or $digits.Length -gt 11) { return "" }
    if ($SelfPhones -contains $digits) { return "" }
    return $digits
}

function ConvertTo-CleanOrderLine {
    param([string]$Line)
    if ($null -eq $Line) { return "" }
    $t = [string]$Line
    # cytaty IMAP/mailowe: >, >>, |, *
    $t = [regex]::Replace($t, '^\s*(?:>+\s*)+', '')
    $t = [regex]::Replace($t, '^\s*[|*\u00A0]+\s*', '')
    $t = [regex]::Replace($t, '(?i)^mailto:\s*', '')
    return $t.Trim()
}

function Test-NameToken {
    <#
      Pewny człon imienia lub nazwiska: Wielka litera i reszta małe.
      Same wielkie litery to za mało (lista do graweru, hasło z oferty, krzyk).
    #>
    param([string]$Token)
    $t = ([string]$Token).Trim('.', ',', ';', ':', '!', '?', '"', "'")
    if ($t.Length -lt 2 -or $t.Length -gt 30) { return $false }
    if ($t -match '[@\d./\\|_]') { return $false }
    if ($t -match '^(?i)(de|von|van|da|di|du)$') { return $true }
    $cap = "^[\p{Lu}][\p{Ll}'’\-]{1,28}$"
    $hyphen = "^[\p{Lu}][\p{Ll}'’\-]{1,20}(-[\p{Lu}][\p{Ll}'’\-]{1,20})+$"
    # -match w PowerShell jest case-insensitive i psuje klasy Lu/Ll.
    return [bool]([regex]::IsMatch($t, $cap) -or [regex]::IsMatch($t, $hyphen))
}

function Test-ValidPersonName {
    param([string]$Name)
    $n = ConvertTo-CleanOrderLine ([regex]::Replace([string]$Name, '\s+', ' ').Trim())
    if ($n.Length -lt 2) { return $false }
    if (Test-LooksLikeHtml $n) { return $false }
    if ($n -match '(?i)^https?://') { return $false }
    if ($n -match '[<>]') { return $false }
    if ($n -match '^[\*>\s\-_,.;:/\\|=]+$') { return $false }
    if ($n -match '(?i)^(Dzie[nń]\s+dobry|Szanowni|Pozdrawiam|Best\s+regards|Kind\s+regards|Adres\s+do|Za[łl][aą]czam|serdecznie)\b') { return $false }
    if ($n -match '(?i)^(In[zż]\.|Mgr\.?|Dr\.?|Prof\.?)(\s|$)') {
        $rest = [regex]::Replace($n, '(?i)^(In[zż]\.|Mgr\.?|Dr\.?|Prof\.?)\s*', '').Trim()
        if ($rest.Length -lt 3) { return $false }
    }
    $letters = ([regex]::Matches($n, '\p{L}')).Count
    if ($letters -lt 2) { return $false }
    $parts = @($n.Split(' ') | Where-Object { $_ })
    foreach ($p in $parts) {
        if (-not (Test-NameToken $p)) { return $false }
    }
    return $true
}

function Split-PersonName {
    param([string]$Full)
    $n = ConvertTo-CleanOrderLine ([regex]::Replace([string]$Full, '\s+', ' ').Trim())
    $n = [regex]::Replace(
        $n,
        '(?i)^(Pozdrawiam|Pozdrawiam serdecznie|Serdecznie pozdrawiam|Z powa[zż]aniem|Best regards|Kind regards|Regards)[,!]?\s*',
        ''
    ).Trim(' ', ',', ';', '.')
    $n = [regex]::Replace($n, '(?i)^<?https?://[^>\s]+>?', ' ').Trim()
    if (-not $n) { return @{ Firstname = ""; Surname = "" } }
    if (-not (Test-ValidPersonName $n)) { return @{ Firstname = ""; Surname = "" } }
    $n = [regex]::Replace($n, '(?i)^(In[zż]\.|Mgr\.?|Dr\.?|Prof\.?)\s+', '').Trim()
    $parts = @($n.Split(' ') | Where-Object { $_ })
    if ($parts.Count -lt 2) { return @{ Firstname = ""; Surname = "" } }
    foreach ($p in $parts) {
        if (-not (Test-NameToken $p)) { return @{ Firstname = ""; Surname = "" } }
    }
    return @{ Firstname = $parts[0]; Surname = ($parts[1..($parts.Count - 1)] -join ' ') }
}

function Remove-QuotedHistory {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return "" }
    $markers = @(
        '^\s*>',
        '^\s*-{2,}\s*(Original Message|Wiadomo[sś][cć] oryginalna|Forwarded message|Przekazana wiadomo[sś][cć])',
        '^\s*_{10,}\s*$',
        '^\s*W dniu .{0,80}napisa[lł]',
        '^\s*Dnia .{0,80}napisa[lł]',
        '^\s*On .{0,80}wrote:\s*$',
        '^\s*(Od|From)\s*:\s*.*@'
    )
    $compiled = foreach ($rx in $markers) { [regex]::new($rx, 'IgnoreCase') }
    $lines = $Text -split "`r?`n"
    $cut = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($rx in $compiled) {
            if ($rx.IsMatch($lines[$i])) { $cut = $i; break }
        }
        if ($cut -ne $lines.Count) { break }
    }
    if ($cut -le 0) { return "" }
    return (($lines[0..($cut - 1)] -join "`n").Trim())
}

function ConvertTo-JsonFile {
    param($Object, [string]$Path, [int]$Depth = 8)
    $json = $Object | ConvertTo-Json -Depth $Depth -Compress:$false
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $json + "`n", $utf8)
}

function Write-Jsonl {
    param($Rows, [string]$Path)
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $sb = New-Object System.Text.StringBuilder
    foreach ($row in @($Rows)) {
        [void]$sb.AppendLine(($row | ConvertTo-Json -Depth 8 -Compress))
    }
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path)) | Out-Null
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), $utf8)
}

function Read-Jsonl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))) {
        if ($line.Trim()) { $rows.Add(($line | ConvertFrom-Json)) }
    }
    return @($rows)
}
