# Signature block + rule extraction. LLM is optional and MUST pass the hallucination guard.

$script:ClosingMarkers = @(
    [regex]'(?i)^\s*(Pozdrawiam|Pozdrawiam serdecznie|Serdecznie pozdrawiam|Z powa[zż]aniem|Z wyrazami szacunku|Best regards|Kind regards|With best regards|Regards|Sincerely)\b'
    [regex]'^\s*--\s*$'
    [regex]'^\s*[-_]{2,}\s*$'
)
$script:LegalForms = [regex]'(?i)\b(sp\.?\s*z\s*\.?\s*o\s*\.?\s*o\.?|sp\.?\s*k\.?|sp\.?\s*j\.?|s\.?\s*a\.?|s\.?\s*c\.?|phu|fhu|sp[oó][lł]ka)\b'
$script:RoleRx = [regex]'(?i)^(Koordynator|Senior|Junior|Manager|Dyrektor|Kierownik|Specjalista|Asystent|Handlowiec|W[lł]a[sś]ciciel|Prezes|Doradca|Konsultant|Biuro)\b.{0,60}$'
$script:StreetRx = [regex]'(?i)^\s*(ul\.?|al\.?|os\.?|pl\.?|plac)\s+.+'
$script:ZipCityRx = [regex]'(?i)^\s*(\d{2}-\d{3})\s+([\w\-'' ]{2,40})\s*$'
$script:PhoneLine = [regex]'(?i)(?:tel\.?|telefon|kom\.?|mobile|fax)\s*[:.]?\s*([+\d][\d\s\-/.()]{6,})'
$script:WwwRx = [regex]'(?i)\b(?:https?://)?(?:www\.)?([a-z0-9][\w\-.]*\.[a-z]{2,}(?:/[^\s]*)?)'

function Get-SignatureHash {
    param([string]$Block)
    $n = [regex]::Replace(($Block | ForEach-Object { $_.ToLowerInvariant() }), '\s+', ' ').Trim()
    if (-not $n) { return "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($n)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-SignatureBlock {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return @{ Block = ""; Method = "empty" } }
    $lines = $Body -split "`r?`n"
    $last = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($rx in $script:ClosingMarkers) {
            if ($rx.IsMatch($lines[$i])) { $last = $i }
        }
    }
    if ($last -ge 0) {
        $end = [Math]::Min($lines.Count - 1, $last + 14)
        $chunk = @($lines[$last..$end])
        while ($chunk.Count -gt 0 -and -not $chunk[-1].Trim()) {
            if ($chunk.Count -eq 1) { $chunk = @(); break }
            $chunk = @($chunk[0..($chunk.Count - 2)])
        }
        return @{ Block = (($chunk -join "`n").Trim()); Method = "closing_marker" }
    }
    $nonempty = @($lines | ForEach-Object { $_.TrimEnd() } | Where-Object { $_.Trim() })
    $take = if ($nonempty.Count -gt 12) { $nonempty[($nonempty.Count - 12)..($nonempty.Count - 1)] } else { $nonempty }
    return @{ Block = (($take -join "`n").Trim()); Method = "tail_fallback" }
}

function Test-LooksLikePersonLine {
    param([string]$Line)
    $n = [regex]::Replace($Line, '\s+', ' ').Trim()
    $n = [regex]::Replace($n, '\s*[–—-]\s*', '-')
    if ($n.Length -lt 3 -or $n.Length -gt 60 -or $n -match '\d' -or $n.Contains('@')) { return $false }
    if ($script:LegalForms.IsMatch($n) -or $script:RoleRx.IsMatch($n) -or $script:StreetRx.IsMatch($n)) { return $false }
    if ($n -match '(?i)^(tel|www|http|nip|regon|ul\.|al\.)') { return $false }
    $parts = @($n.Split(' ') | Where-Object { $_ })
    if ($parts.Count -lt 1 -or $parts.Count -gt 4) { return $false }
    foreach ($p in $parts) {
        $clean = $p.Trim('.', ',', ';', ':')
        if ($clean -match '(?i)^(de|von|van|da|di|du)$') { continue }
        if ($clean -notmatch "^[\w][\w']+(?:-[\w][\w']+)*$") { return $false }
    }
    return $true
}

function Test-LooksLikeCompanyLine {
    param([string]$Line)
    $n = [regex]::Replace($Line, '\s+', ' ').Trim().TrimEnd(',')
    if ($n.Length -lt 2 -or $n.Length -gt 120) { return $false }
    if ($n -match '(?i)^(NIP|REGON|KRS|tel|www|http|Pozdrawiam|Z powa|Best regards)') { return $false }
    if ($script:ZipCityRx.IsMatch($n) -or $script:StreetRx.IsMatch($n) -or $script:RoleRx.IsMatch($n)) { return $false }
    if ($script:LegalForms.IsMatch($n)) { return $true }
    if ($n -match '^\s*\d+\s*[\.\)\-]') { return $false }
    if ($n -match '[-_]{3,}') { return $false }
    if ($n -match '[+"]') { return $false }
    if (Test-LooksLikePersonLine $n) { return $false }
    # Bez formy prawnej sam krzyk (same wielkie) nie jest pewną firmą.
    if (-not [regex]::IsMatch($n, '\p{Ll}')) { return $false }
    $letters = ([regex]::Matches($n, '\w')).Count
    $upper = ([regex]::Matches($n, '[A-ZĄĆĘŁŃÓŚŹŻ]')).Count
    return ($upper -ge [Math]::Max(4, [int]($letters * 0.7))) -and -not $n.Contains('@')
}

function Test-RosterBlock {
    <# Lista samych WIELKICH linii (grawer, notesy) to nie podpis nadawcy. #>
    param([string]$Block)
    $n = 0
    foreach ($ln in ([string]$Block -split "`r?`n")) {
        $t = $ln.Trim()
        if ([regex]::IsMatch($t, '^[\p{Lu}]{2,}(?:\s+[\p{Lu}]{2,}){1,3}$')) { $n++ }
    }
    return ($n -ge 3)
}

function New-ExtractedFields {
    return [PSCustomObject]@{
        firstname  = ""
        surname    = ""
        role       = ""
        company    = ""
        street     = ""
        zip        = ""
        city       = ""
        phones     = @()
        emails     = @()
        www        = ""
        nip        = ""
        regon      = ""
        krs        = ""
        iban       = ""
        confidence = 0.0
        flags      = @()
        evidence   = @{}
    }
}

function Get-ExtractedFromSignature {
    param(
        [string]$Block,
        [string]$FromName = "",
        [string]$FromEmail = "",
        [string[]]$SelfEmails = @(),
        [string[]]$SelfPhones = @()
    )
    $r = New-ExtractedFields
    if ([string]::IsNullOrWhiteSpace($Block)) {
        $r.flags = @('empty_block')
        return $r
    }
    $lines = @($Block -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $blob = $Block

    $nip = Get-NipFromText $blob
    if ($nip) { $r.nip = $nip; $r.evidence['nip'] = $nip }
    $rm = [regex]::Match($blob, '(?i)REGON[:\s]*(\d{9}|\d{14})\b')
    if ($rm.Success -and (Test-RegonChecksum $rm.Groups[1].Value)) {
        $r.regon = $rm.Groups[1].Value
        $r.evidence['regon'] = $rm.Value
    }
    $km = [regex]::Match($blob, '(?i)KRS[:\s]*(\d{5,10})\b')
    if ($km.Success) {
        $r.krs = $km.Groups[1].Value.PadLeft(10, '0')
        $r.evidence['krs'] = $km.Value
    }
    $im = [regex]::Match($blob, '(?i)\b(PL\s?(?:\d{2}\s?)(?:\d{4}\s?){5}\d{4})\b')
    if ($im.Success) {
        $iban = ([regex]::Replace($im.Groups[1].Value, '\s', '')).ToUpperInvariant()
        if (Test-IbanPl $iban) { $r.iban = $iban }
    }

    $phones = New-Object System.Collections.Generic.List[string]
    foreach ($m in $script:PhoneLine.Matches($blob)) {
        $p = ConvertTo-NormalizedPhone $m.Groups[1].Value $SelfPhones
        if ($p -and -not $phones.Contains($p)) { $phones.Add($p) }
    }
    if ($phones.Count -eq 0) {
        $loose = [regex]'(?<!\d)(?:\+48|0048|48)?[\s\-.]*(?:\d[\s\-.]*){9}(?!\d)'
        foreach ($ln in $lines) {
            if ($ln -match '(?i)(NIP|REGON|KRS|IBAN)') { continue }
            foreach ($m in $loose.Matches($ln)) {
                $p = ConvertTo-NormalizedPhone $m.Value $SelfPhones
                if ($p -and -not $phones.Contains($p)) { $phones.Add($p) }
            }
        }
    }
    $r.phones = @($phones)

    $r.emails = @(Get-EmailsInText $blob $SelfEmails)
    $fe = ConvertTo-NormalizedEmail $FromEmail $SelfEmails
    if ($fe -and @($r.emails) -notcontains $fe) {
        $r.emails = @($fe) + @($r.emails)
        $r.flags = @($r.flags) + 'email_from_header'
    }

    $wm = $script:WwwRx.Match($blob)
    if ($wm.Success) {
        $w = $wm.Groups[1].Value.TrimEnd('.', ',', ';', ')', '/')
        $last = ($w -split '\.')[-1]
        $hostOk = $last.Length -ge 2 -and $last.Length -le 4 -and $w -notmatch '^\d+\.'
        if ($hostOk -and $w -notmatch '(?i)^(gmail|wp|onet|o2|interia|outlook|hotmail)\.') {
            $r.www = $w
        }
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $script:ZipCityRx.Match($lines[$i])
        if ($m.Success) {
            $r.zip = $m.Groups[1].Value
            $r.city = $m.Groups[2].Value.Trim()
            if ($i -gt 0 -and ($script:StreetRx.IsMatch($lines[$i - 1]) -or $lines[$i - 1] -match '\d')) {
                $r.street = $lines[$i - 1]
            }
            break
        }
    }
    if (-not $r.street) {
        foreach ($ln in $lines) {
            if ($script:StreetRx.IsMatch($ln)) { $r.street = $ln; break }
        }
    }
    foreach ($ln in $lines) {
        if ($script:RoleRx.IsMatch($ln)) { $r.role = $ln; break }
    }

    $best = ""; $score = -1
    foreach ($ln in $lines) {
        if (-not (Test-LooksLikeCompanyLine $ln)) { continue }
        $s = if ($script:LegalForms.IsMatch($ln)) { 3 } else { 1 }
        if ($s -gt $score) { $best = $ln; $score = $s }
    }
    $r.company = $best

    foreach ($ln in $lines) {
        if ($ln -match '(?i)^(Pozdrawiam|Z powa[zż]aniem|Best regards)\b') {
            $split = Split-PersonName $ln
            if ($split.Firstname) { $r.firstname = $split.Firstname; $r.surname = $split.Surname; break }
        }
        if ((Test-LooksLikePersonLine $ln) -and -not ((Test-LooksLikeCompanyLine $ln) -and $ln -ceq $ln.ToUpperInvariant())) {
            $split = Split-PersonName $ln
            if ($split.Firstname) { $r.firstname = $split.Firstname; $r.surname = $split.Surname; break }
        }
    }
    if (-not $r.firstname -and $FromName) {
        $split = Split-PersonName $FromName
        if ($split.Firstname) {
            $r.firstname = $split.Firstname
            $r.surname = $split.Surname
            $r.flags = @($r.flags) + 'name_from_header'
        }
    }

    $joinedName = ("{0} {1}" -f $r.firstname, $r.surname).Trim()
    $again = Split-PersonName $joinedName
    if (-not $again.Firstname -or -not $again.Surname) {
        if ($r.firstname -or $r.surname) { $r.flags = @($r.flags) + 'uncertain_name' }
        $r.firstname = ""
        $r.surname = ""
    }
    else {
        $r.firstname = $again.Firstname
        $r.surname = $again.Surname
    }
    if (Test-RosterBlock $Block) {
        $r.firstname = ""
        $r.surname = ""
        $r.flags = @($r.flags | Where-Object { $_ -ne 'uncertain_name' }) + 'roster'
    }
    if ($r.company -and -not (Test-LooksLikeCompanyLine $r.company)) {
        $r.flags = @($r.flags) + 'uncertain_company'
        $r.company = ""
    }

    $scoreF = 0.0
    if ($r.firstname) { $scoreF += 0.25 }
    if ($r.surname) { $scoreF += 0.15 }
    if ($r.company) { $scoreF += 0.2 }
    if ($r.nip) { $scoreF += 0.2 }
    if (@($r.phones).Count) { $scoreF += 0.1 }
    if (@($r.emails).Count) { $scoreF += 0.1 }
    if ($r.street -and $r.zip) { $scoreF += 0.1 }
    if ($r.www) { $scoreF += 0.05 }
    $r.confidence = [Math]::Round([Math]::Min($scoreF, 1.0), 2)
    if (-not $r.firstname -and -not $r.company -and -not $r.nip) {
        $r.flags = @($r.flags) + 'weak_identity'
    }
    return $r
}

function Test-NeedsAi {
    param($Extracted, [double]$Threshold = 0.45)
    if (@($Extracted.flags) -contains 'roster') { return $false }
    if (@($Extracted.flags) -contains 'uncertain_name') { return $true }
    if (@($Extracted.flags) -contains 'uncertain_company' -and -not $Extracted.firstname) { return $true }
    if ([double]$Extracted.confidence -lt $Threshold) { return $true }
    if (@($Extracted.flags) -contains 'weak_identity') { return $true }
    if (-not $Extracted.firstname -and -not $Extracted.surname -and -not $Extracted.company) { return $true }
    return $false
}

function Test-GroundedInBlock {
    param([string]$Value, [string]$Source)
    if (-not $Value) { return $true }
    $src = [regex]::Replace($Source, '\s+', '').ToLowerInvariant()
    $val = [regex]::Replace($Value, '\s+', '').ToLowerInvariant()
    $digits = Get-DigitsOnly $Value
    if ($digits.Length -ge 6 -and (Get-DigitsOnly $Source).Contains($digits)) { return $true }
    return $src.Contains($val)
}

function Remove-HallucinatedFields {
    param($Extracted, [string]$Block)
    $dropped = New-Object System.Collections.Generic.List[string]
    foreach ($field in @('firstname', 'surname', 'role', 'company', 'street', 'zip', 'city', 'www', 'nip', 'regon', 'krs', 'iban')) {
        $val = [string]$Extracted.$field
        if ($val -and -not (Test-GroundedInBlock $val $Block)) {
            $Extracted.$field = ""
            $dropped.Add($field)
        }
    }
    $phones = @($Extracted.phones | Where-Object { Test-GroundedInBlock $_ $Block })
    foreach ($p in @($Extracted.phones)) {
        if ($phones -notcontains $p) { $dropped.Add("phone:$p") }
    }
    $Extracted.phones = @($phones)
    $emails = @($Extracted.emails | Where-Object { Test-GroundedInBlock $_ $Block })
    foreach ($e in @($Extracted.emails)) {
        if ($emails -notcontains $e) { $dropped.Add("email:$e") }
    }
    $Extracted.emails = @($emails)
    return @{ Extracted = $Extracted; Dropped = @($dropped) }
}

function Get-SignatureHits {
    param(
        $Messages,
        $SelfEmails = @(),
        $SelfPhones = @(),
        [double]$AiThreshold = 0.45
    )
    $SelfEmails = Get-NormalizedEmailList $SelfEmails
    $SelfPhones = ConvertTo-FlatStringArray $SelfPhones
    $msgList = Get-NormalizedMessageRows $Messages
    $seen = @{}
    foreach ($msg in $msgList) {
        $sig = Get-SignatureBlock $msg.body
        $h = Get-SignatureHash $sig.Block
        if (-not $h) { continue }
        if ($seen.ContainsKey($h)) {
            $seen[$h].count++
            continue
        }
        $extracted = Get-ExtractedFromSignature -Block $sig.Block -FromName $msg.fromName -FromEmail $msg.fromEmail -SelfEmails $SelfEmails -SelfPhones $SelfPhones
        $seen[$h] = [PSCustomObject]@{
            hash           = $h
            count          = 1
            method         = $sig.Method
            block          = $sig.Block
            fromEmail      = $msg.fromEmail
            fromName       = $msg.fromName
            folderKind     = $msg.folderKind
            folderLabel    = $msg.folderLabel
            extracted      = $extracted
            droppedFields  = @()
            model          = ""
        }
    }
    $rules = @()
    $queue = @()
    foreach ($hit in $seen.Values) {
        if (Test-NeedsAi $hit.extracted $AiThreshold) { $queue += $hit } else { $rules += $hit }
    }
    return @{ Rules = $rules; Queue = $queue }
}
