# Polish identifiers: NIP / REGON / IBAN checksums.
# Invariant: never store a NIP that fails the official checksum.

function Get-DigitsOnly {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    return [regex]::Replace($Value, '\D', '')
}

function Test-NipChecksum {
    param([string]$Nip)
    $d = Get-DigitsOnly $Nip
    if ($d.Length -ne 10 -or $d -eq ('0' * 10)) { return $false }
    $w = @(6, 5, 7, 2, 3, 4, 5, 6, 7)
    $total = 0
    for ($i = 0; $i -lt 9; $i++) { $total += [int]::Parse($d[$i].ToString()) * $w[$i] }
    $mod = $total % 11
    if ($mod -eq 10) { return $false }
    return $mod -eq [int]::Parse($d[9].ToString())
}

function Get-NipFromText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $labeled = [regex]::Match($Text, '(?i)(?:NIP[:\s]*)((?:\d[-\s]*){10})\b')
    if ($labeled.Success) {
        $cand = Get-DigitsOnly $labeled.Groups[1].Value
        if (Test-NipChecksum $cand) { return $cand }
    }
    foreach ($m in [regex]::Matches($Text, '(?<!\d)(\d{3}[-\s]\d{3}[-\s]\d{2}[-\s]\d{2}|\d{10})(?!\d)')) {
        $cand = Get-DigitsOnly $m.Groups[1].Value
        if (Test-NipChecksum $cand) { return $cand }
    }
    return ""
}

function Test-RegonChecksum {
    param([string]$Regon)
    $d = Get-DigitsOnly $Regon
    if ($d.Length -eq 9) {
        $w = @(8, 9, 2, 3, 4, 5, 6, 7)
        $total = 0
        for ($i = 0; $i -lt 8; $i++) { $total += [int]::Parse($d[$i].ToString()) * $w[$i] }
        $mod = $total % 11
        if ($mod -eq 10) { $mod = 0 }
        return $mod -eq [int]::Parse($d[8].ToString())
    }
    if ($d.Length -eq 14) {
        if (-not (Test-RegonChecksum $d.Substring(0, 9))) { return $false }
        $w = @(2, 4, 8, 5, 0, 9, 7, 3, 6, 1, 2, 4, 8)
        $total = 0
        for ($i = 0; $i -lt 13; $i++) { $total += [int]::Parse($d[$i].ToString()) * $w[$i] }
        $mod = $total % 11
        if ($mod -eq 10) { $mod = 0 }
        return $mod -eq [int]::Parse($d[13].ToString())
    }
    return $false
}

function Test-IbanPl {
    param([string]$Iban)
    $raw = ([regex]::Replace($Iban, '\s', '')).ToUpperInvariant()
    if ($raw -notmatch '^PL\d{26}$') { return $false }
    $rearranged = $raw.Substring(4) + $raw.Substring(0, 4)
    $numeric = New-Object System.Text.StringBuilder
    foreach ($ch in $rearranged.ToCharArray()) {
        if ($ch -ge 'A' -and $ch -le 'Z') {
            [void]$numeric.Append(([int]$ch - 55).ToString())
        }
        else { [void]$numeric.Append($ch) }
    }
    $rem = 0
    foreach ($ch in $numeric.ToString().ToCharArray()) {
        $rem = ($rem * 10 + [int]::Parse($ch.ToString())) % 97
    }
    return $rem -eq 1
}
