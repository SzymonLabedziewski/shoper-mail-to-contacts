# Which IMAP folders to scan.
# Default: recurse the whole tree (INBOX + every subfolder). No FIRMY/OSOBY required.
# Only Sent / Trash / Junk / Drafts / Archive (name or SPECIAL-USE) are skipped.
# "[Shop]" and custom folders stay IN — order confirmations often live there.

$script:SentTrashRx = [regex]'(?i)(^|[./])(Sent|Wys[lł]ane|Trash|Kosz|Junk|Spam|Drafts|Szkice|Archive|Archiwum|Niechciane|Templates)(/|$|\.)'

function ConvertFrom-FolderClassification {
    param(
        [string]$Name,
        [string]$SpecialUse = "",
        [string]$ExcludeRegex = ""
    )
    $info = [PSCustomObject]@{
        name       = $Name
        specialUse = $SpecialUse
        include    = $true
        reason     = 'inbox_or_custom'
    }
    $su = $SpecialUse.ToLowerInvariant()
    foreach ($flag in @('\sent', '\trash', '\junk', '\drafts', '\archive')) {
        if ($su.Contains($flag)) {
            $info.include = $false
            $info.reason = 'imap_special_use'
            return $info
        }
    }
    if ($script:SentTrashRx.IsMatch($Name) -or ($ExcludeRegex -and $Name -match $ExcludeRegex)) {
        $info.include = $false
        $info.reason = 'name_heuristic'
        return $info
    }
    $lower = $Name.ToLowerInvariant()
    if ($lower -eq 'inbox' -or $lower.EndsWith('/inbox') -or $lower.EndsWith('.inbox')) {
        $info.reason = 'inbox'
    }
    return $info
}

function Select-ImapFolders {
    <#
      Empty Include = every folder except Sent/Trash/Junk/Drafts.
      Covers: only-INBOX, INBOX+subfolders, Shoper FIRMY/OSOBY/[Shop] if present.
    #>
    param(
        [string[]]$Names,
        [string[]]$Include = @(),
        [string]$ExcludeRegex = ""
    )
    $infos = foreach ($n in $Names) {
        if ($n -and $n.Trim()) { ConvertFrom-FolderClassification -Name $n.Trim() -ExcludeRegex $ExcludeRegex }
    }
    $infos = @($infos)
    if ($Include -and $Include.Count -gt 0) {
        $wanted = @($Include | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($info in $infos) {
            $info.include = $wanted -contains $info.name.ToLowerInvariant()
            if ($info.include) { $info.reason = 'explicit_include' }
        }
    }
    return $infos
}

function ConvertTo-FlatStringArray {
    <#
      PowerShell 5.1 lubi „rozpakować” tablice albo złączyć je w jeden string ze spacjami
      przy rzutowaniu na [string[]]. Ta funkcja zawsze zwraca płaską tablicę stringów
      jako JEDEN obiekt (unary comma) — wywołuj BEZ zewnętrznego @(...).
    #>
    param($Value)
    $acc = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.Queue[object]
    foreach ($v in @($Value)) { $pending.Enqueue($v) }
    while ($pending.Count -gt 0) {
        $v = $pending.Dequeue()
        if ($null -eq $v) { continue }
        if ($v -is [string]) {
            if ($v.Length -gt 0) { [void]$acc.Add($v) }
            continue
        }
        # PSCustomObject jest IEnumerable właściwości — nie rozwijaj go
        if ($v -is [System.Management.Automation.PSCustomObject]) {
            continue
        }
        if ($v -is [System.Collections.IDictionary]) { continue }
        if ($v -is [System.Collections.IEnumerable]) {
            foreach ($x in $v) { $pending.Enqueue($x) }
            continue
        }
        $s = [string]$v
        if ($s.Length -gt 0) { [void]$acc.Add($s) }
    }
    , $acc.ToArray()
}

function Get-NormalizedEmailList {
    param($Value)
    $arr = ConvertTo-FlatStringArray $Value
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($e in $arr) {
        $n = $e.Trim().ToLowerInvariant()
        if ($n -and -not $out.Contains($n)) { [void]$out.Add($n) }
    }
    , $out.ToArray()
}

function Get-NormalizedMessageRows {
    <# Flatten accidental nested arrays from pipeline assignment (PS 5.1). #>
    param($Value)
    $acc = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Queue[object]
    foreach ($v in @($Value)) { $pending.Enqueue($v) }
    while ($pending.Count -gt 0) {
        $v = $pending.Dequeue()
        if ($null -eq $v) { continue }
        if ($v -is [System.Management.Automation.PSCustomObject]) {
            [void]$acc.Add($v)
            continue
        }
        if ($v -is [hashtable] -or $v -is [System.Collections.IDictionary]) {
            [void]$acc.Add($v)
            continue
        }
        if ($v -is [System.Collections.IEnumerable] -and $v -isnot [string]) {
            foreach ($x in $v) { $pending.Enqueue($x) }
            continue
        }
    }
    , $acc.ToArray()
}

function ConvertFrom-FolderPickSelection {
    <#
      * / all / wszystkie → wszystkie candidatów.
      Puste → pusta tablica (kreator wymaga jawnego wyboru — bez domyślnego folderu).
      Numery: 1,3  1-3  albo dokładne nazwy (bez spacji w tokenie — lepiej numery).
    #>
    param(
        [string]$InputText,
        $Candidates
    )
    $list = ConvertTo-FlatStringArray $Candidates
    if ($list.Count -eq 0) { return , [string[]]@() }
    $raw = if ($null -eq $InputText) { '' } else { $InputText.Trim() }
    if ($raw -eq '') {
        return , [string[]]@()
    }
    if ($raw -eq '*' -or $raw -match '^(?i)(all|wszystkie|wszystko)$') {
        return , $list
    }
    $picked = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $tokens = @($raw -split '[,;]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($tok in $tokens) {
        if ($tok -match '^(\d+)\s*-\s*(\d+)$') {
            $a = [int]$Matches[1]
            $b = [int]$Matches[2]
            if ($a -gt $b) { $tmp = $a; $a = $b; $b = $tmp }
            for ($i = $a; $i -le $b; $i++) {
                if ($i -ge 1 -and $i -le $list.Count) { [void]$picked.Add($list[$i - 1]) }
            }
            continue
        }
        $num = 0
        if ([int]::TryParse($tok, [ref]$num)) {
            if ($num -ge 1 -and $num -le $list.Count) { [void]$picked.Add($list[$num - 1]) }
            continue
        }
        # spacje w tokenie OK (nazwa folderu) — nie dzielimy po \s
        $exact = @($list | Where-Object { $_.Equals($tok, [StringComparison]::OrdinalIgnoreCase) })
        if ($exact.Count -gt 0) {
            foreach ($e in $exact) { [void]$picked.Add($e) }
            continue
        }
        $partial = @($list | Where-Object { $_.IndexOf($tok, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($partial.Count -eq 1) {
            [void]$picked.Add($partial[0])
            continue
        }
        if ($partial.Count -gt 1) {
            throw "Niejednoznaczna nazwa folderu: '$tok' → $($partial -join ' | ')"
        }
        throw "Nieznany wybór folderu: '$tok' (użyj numeru 1..$($list.Count) albo dokładnej nazwy)."
    }
    if ($picked.Count -eq 0) { throw 'Nic nie wybrano — podaj numery, * (= wszystkie) albo INBOX.' }
    $ordered = @($list | Where-Object { $picked.Contains($_) })
    return , ([string[]]$ordered)
}

function Test-IsInteractiveConsole {
    try {
        if (-not [Environment]::UserInteractive) { return $false }
        if ([Console]::IsInputRedirected) { return $false }
        return $true
    }
    catch { return $true }
}
