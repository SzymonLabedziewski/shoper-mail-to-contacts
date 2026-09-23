# Shop order adapters. `shoper` = proven Polish Shoper confirmation template.
# Subject match is a FRAGMENT anywhere in the subject (Fwd:/Re:/prefix OK).

$script:OrderSubjFragment = [regex]'(?i)potwierdzenie\s+zam\w+wienia'
$script:OrderSubjWithNo = [regex]'(?i)potwierdzenie\s+zam\w+wienia\s+nr:?\s*(\d+)'
$script:ReplySubj = [regex]'(?i)^\s*(Re|Odp|AW)\s*:'

function Test-ShoperOrderSubject {
    param([string]$Subject)
    return $script:OrderSubjFragment.IsMatch([string]$Subject)
}

function Get-FieldLine {
    param([string]$Text, [string]$Pattern)
    $m = [regex]::Match($Text, $Pattern)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ""
}

function ConvertFrom-BuyerBlock {
    param([string]$Block)
    $person = $company = $nip = $zip = $city = $street = ""
    $lines = @(
        $Block -split "`r?`n" |
            ForEach-Object { ConvertTo-CleanOrderLine $_ } |
            Where-Object { $_ -and $_ -notin @('*', ',', '>') }
    )
    if ($lines.Count -eq 0) {
        return @{ Person = ""; Company = ""; Nip = ""; Zip = ""; City = ""; Street = "" }
    }
    $line0 = $lines[0]
    $m = [regex]::Match($line0, '^(?<name>.+?)\s*,\s*(?<rest>\d{2}-\d{3}\s+.+)$')
    if ($m.Success) {
        $person = $m.Groups['name'].Value.Trim()
        $rest = $m.Groups['rest'].Value.Trim()
        $m2 = [regex]::Match($rest, '^(?<zip>\d{2}-\d{3})\s+(?<city>.+?)\s+(?<street>.+)$')
        if ($m2.Success) {
            $zip = $m2.Groups['zip'].Value
            $city = $m2.Groups['city'].Value.Trim()
            $street = $m2.Groups['street'].Value.Trim()
        }
        else {
            $m3 = [regex]::Match($rest, '^(?<zip>\d{2}-\d{3})\s+(?<city>.+)$')
            if ($m3.Success) {
                $zip = $m3.Groups['zip'].Value
                $city = $m3.Groups['city'].Value.Trim()
            }
        }
    }
    else { $person = $line0 }

    if ($lines.Count -ge 2 -and -not $zip) {
        $companyLine = $lines[1]
        $m = [regex]::Match($companyLine, '^(.+?),\s*(\d{10})\s*$')
        if ($m.Success) {
            $company = $m.Groups[1].Value.Trim().Trim(',')
            $nip = $m.Groups[2].Value
        }
        elseif ($companyLine -match '^\s*,\s*$') { $company = "" }
        elseif ($companyLine -match '(\d{10})') {
            $nip = $Matches[1]
            $company = $companyLine.Replace($nip, '').Trim(' ', ',')
        }
        elseif ($companyLine -match '^(\d{2}-\d{3})\s+(.+)$') {
            $zip = $Matches[1]
            $city = $Matches[2].Trim()
            if ($lines.Count -ge 3 -and $lines[2] -notmatch '^\d{2}-\d{3}') { $street = $lines[2] }
        }
        else { $company = $companyLine.Trim().Trim(',') }
    }

    if (-not $zip) {
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^(\d{2}-\d{3})\s+(.+)$') {
                $zip = $Matches[1]
                $city = $Matches[2].Trim()
                if (($i + 1) -lt $lines.Count -and $lines[$i + 1] -notmatch '^\d{2}-\d{3}') {
                    $street = $lines[$i + 1]
                }
                break
            }
        }
    }
    if (-not $nip) { $nip = Get-NipFromText $Block }
    if ($nip -and -not (Test-NipChecksum $nip)) { $nip = "" }
    $person = ConvertTo-CleanOrderLine $person
    $company = ConvertTo-CleanOrderLine $company
    return @{ Person = $person; Company = $company; Nip = $nip; Zip = $zip; City = $city; Street = $street }
}

function ConvertFrom-ShoperOrder {
    param(
        [string]$Body,
        [string]$Subject,
        [string]$Folder = "",
        [string]$Uid = "",
        $SelfEmails = @()
    )
    # Cheap gates first — HTML→plain on every inbox mail was freezing the UI after FETCH.
    $subjectOk = $script:OrderSubjFragment.IsMatch([string]$Subject)
    $isReply = $script:ReplySubj.IsMatch([string]$Subject)
    if (-not $subjectOk) {
        if ([string]::IsNullOrEmpty($Body) -or $Body -notmatch '(?i)Dane zamawiaj') { return $null }
    }

    $SelfEmails = Get-NormalizedEmailList $SelfEmails
    $plain = if (Test-LooksLikeHtml $Body) { ConvertFrom-HtmlToPlain $Body } else { $Body }
    $orderNo = ""
    $sm = $script:OrderSubjWithNo.Match([string]$Subject)
    if ($sm.Success) { $orderNo = $sm.Groups[1].Value }
    else {
        $sm2 = [regex]::Match([string]$Subject, '(?i)nr:?\s*(\d+)')
        if ($sm2.Success -and $subjectOk) {
            $orderNo = $sm2.Groups[1].Value
        }
        else {
            $bm = [regex]::Match($plain, '(?i)zam\w+wienie,?\s*nr\.?\s*(\d+)')
            if ($bm.Success) { $orderNo = $bm.Groups[1].Value }
        }
    }

    $client = ConvertTo-CleanOrderLine (Get-FieldLine $plain '(?im)^(?:>+\s*)*Klient:\s*(.+)$')
    $emailRaw = ConvertTo-CleanOrderLine (Get-FieldLine $plain '(?im)^(?:>+\s*)*E-?mail:\s*(.+)$')
    $email = ConvertTo-NormalizedEmail $emailRaw $SelfEmails
    $phone = ConvertTo-NormalizedPhone (Get-FieldLine $plain '(?im)^(?:>+\s*)*Telefon:\s*(.+)$')

    $personName = $companyRaw = $nip = $zip = $city = $street = ""
    $blockM = [regex]::Match($plain, '(?is)(?:>+\s*)*Dane zamawiaj\w{0,2}cego:\s*(.*?)\s*(?=(?:>+\s*)*Dane do wysy\wki:|(?:>+\s*)*zam\w+wione produkty:|$)')
    if ($blockM.Success) {
        $b = ConvertFrom-BuyerBlock $blockM.Groups[1].Value
        $personName = ConvertTo-CleanOrderLine $b.Person
        $companyRaw = ConvertTo-CleanOrderLine $b.Company
        $nip = $b.Nip
        $zip = $b.Zip
        $city = $b.City
        $street = ConvertTo-CleanOrderLine $b.Street
    }
    # Preferuj "Klient:" gdy blok ma śmieci / puste imię
    if ($client -and ((-not $personName) -or -not (Test-ValidPersonName $personName))) {
        $personName = $client
    }
    if (-not $nip -and $companyRaw) { $nip = Get-NipFromText $companyRaw }
    if ($nip -and -not (Test-NipChecksum $nip)) { $nip = "" }

    $hasBuyer = $plain -match '(?i)Dane zamawiaj'
    if (-not $subjectOk -and -not $hasBuyer) { return $null }
    if ($isReply -and -not $email) { return $null }
    if (-not $email -and -not $personName -and -not $orderNo) { return $null }

    $split = Split-PersonName $personName
    # jeśli Split odrzucił (cytaty), spróbuj Klient:
    if ((-not $split.Firstname) -and $client -and $client -ne $personName) {
        $split = Split-PersonName $client
        if ($split.Firstname) { $personName = $client }
    }
    return [PSCustomObject]@{
        orderNo     = $orderNo
        subject     = $Subject
        folder      = $Folder
        uid         = $Uid
        clientName  = $client
        personName  = $personName
        firstname   = $split.Firstname
        surname     = $split.Surname
        email       = $email
        phone       = $phone
        companyRaw  = $companyRaw
        nip         = $nip
        zip         = $zip
        city        = $city
        street      = $street
    }
}

function Get-CompaniesFromOrders {
    param($Orders)
    $buckets = @{}
    $names = @{}
    foreach ($o in @($Orders)) {
        if (-not $o.nip) { continue }
        $key = [string]$o.nip
        if (-not $buckets.ContainsKey($key)) { $buckets[$key] = @{}; $names[$key] = @{} }
        $raw = ([string]$o.companyRaw).Trim()
        if (-not $raw) { continue }
        $nk = $raw.ToLowerInvariant()
        if (-not $buckets[$key].ContainsKey($nk)) { $buckets[$key][$nk] = 0 }
        $buckets[$key][$nk]++
        if (-not $names[$key].ContainsKey($nk) -or $raw.Length -gt $names[$key][$nk].Length) {
            $names[$key][$nk] = $raw
        }
    }
    $out = foreach ($nip in ($buckets.Keys | Sort-Object)) {
        $variants = @($buckets[$nip].GetEnumerator() | Sort-Object { -$_.Value }, { -$names[$nip][$_.Key].Length })
        $canonical = if ($variants) { $names[$nip][$variants[0].Key] } else { "" }
        $aliases = @()
        $counts = @()
        foreach ($v in $variants) {
            $counts += [PSCustomObject]@{ name = $names[$nip][$v.Key]; count = $v.Value }
            if ($names[$nip][$v.Key] -ne $canonical) { $aliases += $names[$nip][$v.Key] }
        }
        [PSCustomObject]@{
            nip            = $nip
            canonicalName  = $canonical
            aliases        = @($aliases)
            variantCounts  = @($counts)
        }
    }
    return @($out)
}

function ConvertTo-ContactsFromOrders {
    param($Orders, $Companies)
    $canon = @{}
    foreach ($c in @($Companies)) { $canon[[string]$c.nip] = $c.canonicalName }
    $contacts = @()
    $byEmail = @{}

    foreach ($o in @($Orders)) {
        $org = if ($o.nip -and $canon.ContainsKey([string]$o.nip)) { $canon[[string]$o.nip] } else { $o.companyRaw }
        $idx = -1
        if ($o.email -and $byEmail.ContainsKey($o.email)) { $idx = $byEmail[$o.email] }
        elseif ($o.nip) {
            $pn = [regex]::Replace([string]$o.personName, '\s+', ' ').Trim().ToLowerInvariant()
            for ($i = 0; $i -lt $contacts.Count; $i++) {
                $c = $contacts[$i]
                if ($c.nip -eq $o.nip -and $o.nip) {
                    $cn = ("$($c.firstname) $($c.surname)").Trim().ToLowerInvariant()
                    if ($cn -eq $pn -or @($c.personNames) -contains $o.personName) { $idx = $i; break }
                }
            }
        }
        if (-not $o.email -and -not $o.nip -and -not $o.personName) { continue }
        $pNames = @(); if ($o.personName) { $pNames = @($o.personName) }
        $pEmails = @(); if ($o.email) { $pEmails = @($o.email) }
        $pPhones = @(); if ($o.phone) { $pPhones = @($o.phone) }
        $pNips = @(); if ($o.nip) { $pNips = @($o.nip) }
        $pOrders = @(); if ($o.orderNo) { $pOrders = @($o.orderNo) }
        if ($idx -lt 0) {
            $c = [PSCustomObject]@{
                id             = ""
                firstname      = $o.firstname
                surname        = $o.surname
                personNames    = $pNames
                emails         = $pEmails
                phones         = $pPhones
                organization   = [string]$org
                nip            = [string]$o.nip
                nips           = $pNips
                companyAliases = @()
                address        = [PSCustomObject]@{ street = $o.street; zip = $o.zip; city = $o.city; country = 'Polska'; region = '' }
                orderIds       = $pOrders
                sources        = @([PSCustomObject]@{ folder = $o.folder; uid = $o.uid; orderNo = $o.orderNo; kind = ''; hash = ''; match = ''; fromEmail = ''; folderKind = ''; folderLabel = '' })
                mergeFlags     = @()
                notes          = ""
            }
            $contacts += $c
            if ($o.email) { $byEmail[$o.email] = $contacts.Count - 1 }
        }
        else {
            $c = $contacts[$idx]
            if ($o.email -and @($c.emails) -notcontains $o.email) {
                $c.emails = @($c.emails) + $o.email
                $byEmail[$o.email] = $idx
            }
            if ($o.phone -and @($c.phones) -notcontains $o.phone) { $c.phones = @($c.phones) + $o.phone }
            if ($o.personName -and @($c.personNames) -notcontains $o.personName) { $c.personNames = @($c.personNames) + $o.personName }
            if ($o.orderNo -and @($c.orderIds) -notcontains $o.orderNo) { $c.orderIds = @($c.orderIds) + $o.orderNo }
            if ($o.nip -and @($c.nips) -notcontains $o.nip) { $c.nips = @($c.nips) + $o.nip }
            if ($o.nip -and -not $c.nip) { $c.nip = $o.nip }
            if ($org -and -not $c.organization) { $c.organization = $org }
            $c.sources = @($c.sources) + [PSCustomObject]@{ folder = $o.folder; uid = $o.uid; orderNo = $o.orderNo; kind = ''; hash = ''; match = ''; fromEmail = ''; folderKind = ''; folderLabel = '' }
        }
    }

    $i = 1
    foreach ($c in $contacts) {
        $c.id = ('C{0:D4}' -f $i)
        $noteLines = @()
        foreach ($n in @($c.nips)) { $noteLines += "NIP: $n" }
        if (@($c.orderIds).Count -gt 0) { $noteLines += ('Zamowienia: ' + (@($c.orderIds) -join ', ')) }
        $c.notes = ($noteLines -join "`n")
        $i++
    }
    return [PSCustomObject]@{
        exportedAt   = (Get-Date).ToString('o')
        contactCount = $contacts.Count
        contacts     = @($contacts)
    }
}
