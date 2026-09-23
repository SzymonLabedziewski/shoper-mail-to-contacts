# Merge signature hits into the order-based book. Prefer two cards over fusing two people.

function Test-MixedPeople {
    param($Contact, [string]$First, [string]$Last)
    if (-not $First -or -not $Last -or -not $Contact.firstname -or -not $Contact.surname) { return $false }
    $a = "$($Contact.firstname) $($Contact.surname)".ToLowerInvariant()
    $b = "$First $Last".ToLowerInvariant()
    return ($a -ne $b) -and ($Contact.surname.ToLowerInvariant() -ne $Last.ToLowerInvariant())
}

function Get-ContactNotes {
    param($Contact)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($n in @($Contact.nips)) { if ($n) { $lines.Add("NIP: $n") } }
    if (@($Contact.orderIds).Count -gt 0) { $lines.Add('Zamowienia: ' + (@($Contact.orderIds) -join ', ')) }
    return ($lines -join "`n")
}

function Merge-SignatureHits {
    param(
        $Book,
        $Hits,
        $SelfEmails = @()
    )
    $SelfEmails = Get-NormalizedEmailList $SelfEmails
    $byEmail = @{}
    $byNip = @{}
    foreach ($c in @($Book.contacts)) {
        foreach ($e in @($c.emails)) { $byEmail[$e.ToLowerInvariant()] = $c }
        if ($c.nip) {
            if (-not $byNip.ContainsKey($c.nip)) { $byNip[$c.nip] = @() }
            $byNip[$c.nip] = @($byNip[$c.nip]) + $c
        }
    }
    $newId = 1
    foreach ($hit in @($Hits)) {
        $ext = $hit.extracted
        $emails = @($ext.emails | ForEach-Object { ConvertTo-NormalizedEmail $_ $SelfEmails } | Where-Object { $_ })
        $fe = ConvertTo-NormalizedEmail $hit.fromEmail $SelfEmails
        if ($fe -and $emails -notcontains $fe) { $emails += $fe }

        $target = $null
        $match = 'new'
        foreach ($e in $emails) {
            if ($byEmail.ContainsKey($e)) { $target = $byEmail[$e]; $match = 'email'; break }
        }
        if ($null -eq $target -and $ext.nip -and $byNip.ContainsKey($ext.nip)) {
            $target = $byNip[$ext.nip][0]
            $match = 'nip'
        }
        if ($null -eq $target -and @($ext.phones).Count -gt 0) {
            foreach ($c in @($Book.contacts)) {
                $overlap = @($c.phones | Where-Object { @($ext.phones) -contains $_ })
                if ($overlap.Count -eq 0) { continue }
                if (Test-MixedPeople $c $ext.firstname $ext.surname) { continue }
                $target = $c
                $match = 'phone'
                break
            }
        }

        $src = [PSCustomObject]@{
            folder = ''; uid = ''; orderNo = ''
            kind = 'signature'; hash = $hit.hash; match = $match
            fromEmail = $hit.fromEmail; folderKind = $hit.folderKind; folderLabel = $hit.folderLabel
        }

        if ($null -eq $target) {
            $pn = @()
            $nm = ("$($ext.firstname) $($ext.surname)").Trim()
            if ($ext.firstname) { $pn = @($nm) }
            $nipsArr = @()
            if ($ext.nip) { $nipsArr = @($ext.nip) }
            $c = [PSCustomObject]@{
                id             = ('S{0:D4}' -f $newId)
                firstname      = $ext.firstname
                surname        = $ext.surname
                personNames    = $pn
                emails         = @($emails)
                phones         = @($ext.phones)
                organization   = [string]$ext.company
                nip            = [string]$ext.nip
                nips           = $nipsArr
                companyAliases = @()
                address        = [PSCustomObject]@{ street = $ext.street; zip = $ext.zip; city = $ext.city; country = 'Polska'; region = '' }
                orderIds       = @()
                sources        = @($src)
                mergeFlags     = @('fromSignature', 'newContact')
                notes          = ""
            }
            $c.notes = Get-ContactNotes $c
            $Book.contacts = @($Book.contacts) + $c
            $Book.contactCount = @($Book.contacts).Count
            $newId++
            foreach ($e in $emails) { $byEmail[$e] = $c }
            if ($c.nip) {
                if (-not $byNip.ContainsKey($c.nip)) { $byNip[$c.nip] = @() }
                $byNip[$c.nip] = @($byNip[$c.nip]) + $c
            }
            continue
        }

        if (Test-MixedPeople $target $ext.firstname $ext.surname) { continue }
        foreach ($e in $emails) {
            if (@($target.emails) -notcontains $e) {
                $target.emails = @($target.emails) + $e
                $byEmail[$e] = $target
            }
        }
        foreach ($p in @($ext.phones)) {
            if ($p -and @($target.phones) -notcontains $p) { $target.phones = @($target.phones) + $p }
        }
        if ($ext.company -and -not $target.organization) { $target.organization = $ext.company }
        if ($ext.nip) {
            if (@($target.nips) -notcontains $ext.nip) { $target.nips = @($target.nips) + $ext.nip }
            if (-not $target.nip) { $target.nip = $ext.nip }
        }
        if ($ext.street -and -not $target.address.street) {
            $target.address.street = $ext.street
            $target.address.zip = $ext.zip
            $target.address.city = $ext.city
        }
        if (@($target.mergeFlags) -notcontains 'fromSignature') { $target.mergeFlags = @($target.mergeFlags) + 'fromSignature' }
        if (@($target.emails).Count -gt 1 -and @($target.mergeFlags) -notcontains 'multiEmail') {
            $target.mergeFlags = @($target.mergeFlags) + 'multiEmail'
        }
        $target.sources = @($target.sources) + $src
        $target.notes = Get-ContactNotes $target
    }
    $Book.contactCount = @($Book.contacts).Count
    return $Book
}
