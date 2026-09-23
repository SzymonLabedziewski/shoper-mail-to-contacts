function ConvertTo-VcfEscape {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    return ($Value -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,' -replace "`r?`n", '\n')
}

function ConvertTo-VCard {
    param($Contact)
    $fn = ("$($Contact.firstname) $($Contact.surname)").Trim()
    if (-not $fn -and @($Contact.emails).Count) { $fn = $Contact.emails[0] }
    if (-not $fn) { $fn = 'Unknown' }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('BEGIN:VCARD')
    $lines.Add('VERSION:3.0')
    $lines.Add("N:$(ConvertTo-VcfEscape $Contact.surname);$(ConvertTo-VcfEscape $Contact.firstname);;;")
    $lines.Add("FN:$(ConvertTo-VcfEscape $fn)")
    if ($Contact.organization) { $lines.Add("ORG:$(ConvertTo-VcfEscape $Contact.organization)") }
    foreach ($e in @($Contact.emails)) { $lines.Add("EMAIL:$(ConvertTo-VcfEscape $e)") }
    foreach ($p in @($Contact.phones)) { $lines.Add("TEL:$(ConvertTo-VcfEscape $p)") }
    $a = $Contact.address
    if ($a -and ($a.street -or $a.city -or $a.zip)) {
        $lines.Add("ADR:;;$(ConvertTo-VcfEscape $a.street);$(ConvertTo-VcfEscape $a.city);;$(ConvertTo-VcfEscape $a.zip);$(ConvertTo-VcfEscape $a.country)")
    }
    if ($Contact.notes) { $lines.Add("NOTE:$(ConvertTo-VcfEscape $Contact.notes)") }
    $lines.Add('END:VCARD')
    return ($lines -join "`r`n")
}

function ConvertTo-ContactBookVcf {
    param($Book)
    $cards = foreach ($c in @($Book.contacts)) { ConvertTo-VCard $c }
    return (($cards -join "`r`n") + "`r`n")
}

function ConvertTo-ContactBookCsvRows {
    param($Book)
    foreach ($c in @($Book.contacts)) {
        [PSCustomObject]@{
            id           = $c.id
            firstname    = $c.firstname
            surname      = $c.surname
            emails       = (@($c.emails) -join '; ')
            phones       = (@($c.phones) -join '; ')
            organization = $c.organization
            nip          = $c.nip
            street       = $c.address.street
            zip          = $c.address.zip
            city         = $c.address.city
            notes        = (([string]$c.notes) -replace "`r?`n", ' | ')
        }
    }
}

function Export-ContactBookCsv {
    param($Book, [string]$Path)
    $rows = @(ConvertTo-ContactBookCsvRows $Book)
    $dir = Split-Path -Parent $Path
    if ($dir) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8
}
