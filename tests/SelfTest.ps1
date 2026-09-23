#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$modDir = Join-Path $RepoRoot 'src\modules'
@(
    'Ui.ps1', 'PlIds.ps1', 'TextUtil.ps1', 'Providers.ps1', 'FolderPolicy.ps1',
    'Orders.ps1', 'Signatures.ps1', 'Merge.ps1', 'Export.ps1',
    'Config.ps1', 'Ollama.ps1', 'ImapClient.ps1', 'Pipeline.ps1'
) | ForEach-Object { . (Join-Path $modDir $_) }

$Failed = 0
function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host "OK   $Name" -ForegroundColor Green }
    else { Write-Host "FAIL $Name" -ForegroundColor Red; $script:Failed++ }
}

# --- checksums ---
Assert-True (Test-NipChecksum '5252345675') 'NIP valid 5252345675'
Assert-True (-not (Test-NipChecksum '5252345678')) 'NIP invalid 5252345678'
Assert-True (-not (Test-NipChecksum '1234567890')) 'NIP invalid 1234567890'
Assert-True (Test-RegonChecksum '123456785') 'REGON 9'
Assert-True (Test-IbanPl 'PL07 1750 1019 0000 0000 2511 0692') 'IBAN PL ok'
Assert-True (-not (Test-IbanPl 'PL00 0000 0000 0000 0000 0000 0000')) 'IBAN PL bad'

# --- Shoper orders ---
$fetched = Join-Path $RepoRoot 'samples\fetched'
$o1body = [IO.File]::ReadAllText((Join-Path $fetched 'order-1001-shoper.txt'), [Text.UTF8Encoding]::new($false))
$o1 = ConvertFrom-ShoperOrder $o1body 'Potwierdzenie zamówienia nr: 1001' 'INBOX' '101'
Assert-True ($null -ne $o1 -and $o1.orderNo -eq '1001') 'order 1001 parsed'
Assert-True ($o1.email -eq 'jan.kowalski@example.com') 'order 1001 email'
Assert-True ($o1.firstname -eq 'Jan' -and $o1.city -eq 'Warszawa') 'order 1001 person/city'

$o2body = [IO.File]::ReadAllText((Join-Path $fetched 'order-1002-shoper.txt'), [Text.UTF8Encoding]::new($false))
$o2 = ConvertFrom-ShoperOrder $o2body 'Potwierdzenie zamówienia nr: 1002'
Assert-True ($o2.nip -eq '5252345675') 'order 1002 NIP checksummed'
Assert-True ($o2.email -eq 'anna.nowak@example.com') 'order 1002 email'
Assert-True ($o2.companyRaw -match 'Example') 'order 1002 company'

# --- signatures ---
$companyMail = [IO.File]::ReadAllText((Join-Path $fetched 'mail-company-signature.txt'), [Text.UTF8Encoding]::new($false))
$sig = Get-SignatureBlock $companyMail
Assert-True ($sig.Method -eq 'closing_marker') 'signature closing_marker'
$ext = Get-ExtractedFromSignature -Block $sig.Block -FromName 'Anna Nowak' -FromEmail 'anna.nowak@example.com'
Assert-True ($ext.firstname -eq 'Anna' -and $ext.surname -eq 'Nowak') 'sig name'
Assert-True ($ext.nip -eq '5252345675') 'sig NIP'
Assert-True ($ext.company -match 'Example') 'sig company'
Assert-True ($ext.confidence -ge 0.45) 'sig confidence'

$quoted = [IO.File]::ReadAllText((Join-Path $fetched 'mail-quoted-thread.txt'), [Text.UTF8Encoding]::new($false))
$body = Remove-QuotedHistory $quoted
Assert-True ($body -match 'Dziękuję') 'quoted kept new text'
Assert-True ($body -notmatch 'sklep@example.com') 'quoted stripped history'

$ghost = New-ExtractedFields
$ghost.firstname = 'Anna'
$ghost.nip = '1111111111'
$ghost.emails = @('ghost@example.com')
$g = Remove-HallucinatedFields $ghost ("Pozdrawiam`nAnna")
Assert-True (-not $g.Extracted.nip) 'hallucinated NIP dropped'
Assert-True ($g.Dropped -contains 'nip') 'dropped list has nip'
Assert-True ($g.Extracted.firstname -eq 'Anna') 'grounded firstname kept'

# --- folders ---
Assert-True (-not (ConvertFrom-FolderClassification 'INBOX.Sent').include) 'exclude Sent'
Assert-True (-not (ConvertFrom-FolderClassification 'INBOX.Trash').include) 'exclude Trash'
Assert-True ((ConvertFrom-FolderClassification 'INBOX').include) 'include INBOX'
Assert-True ((ConvertFrom-FolderClassification 'INBOX.Klienci').include) 'include custom'
$generic = [IO.File]::ReadAllLines((Join-Path $RepoRoot 'samples\mailboxes\generic-folders.txt'), [Text.UTF8Encoding]::new($false))
$infos = Select-ImapFolders -Names $generic -Include @() -ExcludeRegex ''
$scan = @($infos | Where-Object include | ForEach-Object { $_.name })
$skip = @($infos | Where-Object { -not $_.include } | ForEach-Object { $_.name })
Assert-True ($scan -contains 'INBOX' -and $scan -contains 'INBOX.Klienci') 'generic scan set'
Assert-True ($skip -contains 'INBOX.Sent') 'generic skip Sent'

# Flat mailbox: only INBOX (no FIRMY / OSOBY) must still work
$inboxOnly = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'samples\mailboxes\inbox-only.txt') -Encoding UTF8)
$infosFlat = Select-ImapFolders -Names $inboxOnly -Include @() -ExcludeRegex ''
$scanFlat = @($infosFlat | Where-Object include | ForEach-Object { $_.name })
$skipFlat = @($infosFlat | Where-Object { -not $_.include } | ForEach-Object { $_.name })
Assert-True ($scanFlat -contains 'INBOX' -and $scanFlat.Count -eq 1) 'inbox-only scans INBOX alone'
Assert-True ($skipFlat -contains 'INBOX.Sent' -and $skipFlat -contains 'INBOX.Trash') 'inbox-only skips Sent/Trash'

# Folder pick selection (wizard)
$cands = @('INBOX', 'INBOX.FIRMY', 'INBOX.Klienci', 'INBOX.Shop')
$allPick = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText '*' -Candidates $cands)
Assert-True ($allPick.Count -eq 4 -and $allPick[0] -eq 'INBOX') 'pick * = all (flat array)'
$emptyPick = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText '' -Candidates $cands)
Assert-True ($emptyPick.Count -eq 0) 'pick empty = none (no default folder)'
$numPick = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText '1,3' -Candidates $cands)
Assert-True ($numPick.Count -eq 2 -and $numPick[0] -eq 'INBOX' -and $numPick[1] -eq 'INBOX.Klienci') 'pick 1,3'
$rangePick = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText '2-3' -Candidates $cands)
Assert-True ($rangePick.Count -eq 2 -and $rangePick[0] -eq 'INBOX.FIRMY') 'pick range 2-3'
$namePick = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText 'INBOX.Shop' -Candidates $cands)
Assert-True ($namePick.Count -eq 1 -and $namePick[0] -eq 'INBOX.Shop') 'pick by name'
$spaceName = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText 'INBOX.FIRMY.3Z Sp z oo' -Candidates @('INBOX', 'INBOX.FIRMY.3Z Sp z oo'))
Assert-True ($spaceName.Count -eq 1 -and $spaceName[0] -eq 'INBOX.FIRMY.3Z Sp z oo') 'pick name with spaces'
# regression: @(ConvertFrom...) must not collapse many folders into one space-joined string
$many = @(ConvertFrom-FolderPickSelection -InputText '*' -Candidates $cands)
$many = ConvertTo-FlatStringArray $many
Assert-True ($many.Count -eq 4) 'many folders stay Count=4 after flatten'
Assert-True ($many[0].Length -lt 20 -and $many[0] -eq 'INBOX') 'first element is INBOX not joined blob'
# nested message rows must flatten (HashSet[string] would throw on member-enumeration)
$nested = , @([PSCustomObject]@{ messageId = 'a@x'; body = 'x' }, [PSCustomObject]@{ messageId = 'b@x'; body = 'y' })
$flatRows = Get-NormalizedMessageRows $nested
Assert-True ($flatRows.Count -eq 2 -and $flatRows[0].messageId -eq 'a@x') 'normalize nested message rows'
$seenIds = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($m in $flatRows) { Assert-True ($seenIds.Add([string]$m.messageId)) 'hashset accepts string messageId' }

# Shoper optional folders stay IN (Shop is NOT trash)
$shoper = @(Get-Content -LiteralPath (Join-Path $RepoRoot 'samples\mailboxes\shoper-folders.txt') -Encoding UTF8)
$infosShop = Select-ImapFolders -Names $shoper -Include @() -ExcludeRegex ''
$scanShop = @($infosShop | Where-Object include | ForEach-Object { $_.name })
Assert-True ($scanShop -contains 'INBOX') 'shoper keeps INBOX'
Assert-True (($scanShop | Where-Object { $_ -like '*Shop*' }).Count -ge 1) 'shoper keeps [Shop] folder'
Assert-True (($scanShop | Where-Object { $_ -like '*FIRMY*' }).Count -ge 1) 'shoper keeps FIRMY if present'

# Order subject = fragment anywhere in the title
$fragBody = [IO.File]::ReadAllText((Join-Path $fetched 'order-1001-shoper.txt'), [Text.UTF8Encoding]::new($false))
$frag = ConvertFrom-ShoperOrder $fragBody 'Fwd: Sklep — Potwierdzenie zamówienia nr: 1001 (kopia)' 'INBOX' '999'
Assert-True ($null -ne $frag -and $frag.orderNo -eq '1001') 'order subject fragment with Fwd:'
Assert-True ($frag.email -eq 'jan.kowalski@example.com') 'order fragment still parses email'

# --- providers (Shoper only — docs/providers.md) ---
$p = Get-ShoperImapPreset
Assert-True ($p.Host -eq 's.mail.dcsaas.net' -and [int]$p.Port -eq 143) 'shoper host/port'
Assert-True ($p.Tls -eq 'starttls') 'shoper starttls'
Assert-True ($p.Note -match 'STARTTLS') 'shoper note'

# --- wizard config (Shoper only, no Read-Host) ---
$wiz = New-AppConfigFromAnswers -Email 'sklep@piatekaga.pl'
Assert-True ($wiz.imap.host -eq 's.mail.dcsaas.net' -and [int]$wiz.imap.port -eq 143) 'wizard shoper host/port'
Assert-True ($wiz.imap.tls -eq 'starttls') 'wizard shoper starttls'
Assert-True ($wiz.imap.user -eq 'sklep@piatekaga.pl') 'wizard user'
Assert-True (@($wiz.self.emails) -contains 'sklep@piatekaga.pl') 'wizard self.emails'
Assert-True ($wiz.orders.adapter -eq 'shoper') 'wizard adapter stays shoper'
Assert-True (($null -eq $wiz.folders.include) -or (@($wiz.folders.include | Where-Object { $_ }).Count -eq 0)) 'wizard include empty = whole tree'

# --- offline pipeline ---
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('mtc-' + [guid]::NewGuid().ToString('n'))
try {
    $pipeCfg = Get-DefaultConfig
    $book = Invoke-OfflinePipeline -FetchedDir $fetched -OutDir $tmp -Config $pipeCfg
    $emails = @($book.contacts | ForEach-Object { $_.emails } | ForEach-Object { $_ })
    Assert-True ($emails -contains 'jan.kowalski@example.com') 'pipeline jan'
    Assert-True ($emails -contains 'anna.nowak@example.com') 'pipeline anna'
    Assert-True ($emails -contains 'piotr.zielinski@example.com') 'pipeline piotr'
    $anna = @($book.contacts | Where-Object { $_.emails -contains 'anna.nowak@example.com' })[0]
    Assert-True ($anna.nip -eq '5252345675') 'pipeline anna NIP'
    Assert-True (@($book.contacts | Where-Object { $_.emails -contains 'biuro@example.com' }).Count -ge 1) 'pipeline biuro merged'
    $vcf = [IO.File]::ReadAllText((Join-Path $tmp 'contacts.vcf'), [Text.UTF8Encoding]::new($false))
    Assert-True ($vcf -match 'BEGIN:VCARD') 'vcf begin'
    Assert-True ($vcf -match 'NIP: 5252345675') 'vcf NIP'
    Assert-True ($vcf -notmatch 'Podpisy:') 'vcf has no signature hashes'
    $allNotes = @($book.contacts | ForEach-Object { [string]$_.notes }) -join "`n"
    Assert-True ($allNotes -notmatch 'Podpisy:') 'contact notes have no signature hashes'

    $cfgPath = Join-Path $tmp 'config.json'
    Save-AppConfig -Config $wiz -Path $cfgPath
    $rawCfg = [IO.File]::ReadAllText($cfgPath, [Text.UTF8Encoding]::new($false))
    Assert-True ($rawCfg -notmatch '(?i)password') 'saved config has no password'
    Assert-True ($rawCfg -match '"emails": \["sklep@piatekaga.pl"\]') 'saved emails stay an array'
    $round = Read-AppConfig $cfgPath
    Assert-True ($round.imap.host -eq 's.mail.dcsaas.net') 'roundtrip host'
    Assert-True (@($round.self.emails) -contains 'sklep@piatekaga.pl') 'roundtrip self.emails'
    Assert-True ([bool]$round.signatures.enabled) 'default signatures ON (orders + rest of mail)'
    Assert-True (-not [bool]$round.signatures.useOllama) 'default Ollama OFF (rules first)'
    Assert-True (Test-ShoperOrderSubject 'Potwierdzenie zamówienia nr: 12') 'order subject fragment'
    Assert-True (-not (Test-ShoperOrderSubject 'Re: wycena 50 szt.')) 'non-order subject'
    Assert-True (-not (Test-ValidPersonName 'Dzień dobry')) 'reject greeting as name'
    Assert-True (-not (Test-ValidPersonName '/')) 'reject slash as name'
    Assert-True ((Split-PersonName 'Inż. Mariusz Staniek').Firstname -eq 'Mariusz') 'strip Inż. title'
    Assert-True (-not (Split-PersonName 'Sincerely').Firstname) 'reject closing word as name'
    Assert-True (-not (Split-PersonName 'miłego dnia').Firstname) 'reject lowercase phrase as name'
    Assert-True (-not (Split-PersonName 'adamston@wp.pl').Firstname) 'reject email as name'
    Assert-True (-not (Split-PersonName 'Polityka prywatności www').Firstname) 'reject sentence as name'
    Assert-True ((Split-PersonName 'Beata Jańczewska').Surname -eq 'Jańczewska') 'keep certain surname'
    Assert-True ((Split-PersonName 'Adrian Robak').Firstname -eq 'Adrian') 'keep title-case name'
    Assert-True (-not (Split-PersonName 'ZAPAKOWANA NA PREZENT').Firstname) 'reject shouted product line'
    Assert-True (-not (Split-PersonName 'LIŻEWSKI MIROSŁAW').Firstname) 'reject all-caps roster line'
    Assert-True (-not (Test-LooksLikeCompanyLine '6. DODATKOWA USŁUGA ----ZAPAKUJ NA PREZENT---KAŻDA')) 'reject offer line as company'

# Real Shoper order body (user sample) + quoted reply noise
$psineBody = @"
W Twoim sklepie zostalo zlozone nowe zamowienie, nr 1682

Informacje podstawowe:
Klient: Marek Majewski
E-mail: kontakt@psine.pl

Dane zamawiajacego:
Marek Majewski
PSINE.PL Marek Majewski, 6572125912
25-019 Kielce
ul.Karczowkowska 8A

Dane do wysylki:
Marek Majewski
"@
$psine = ConvertFrom-ShoperOrder -Body $psineBody -Subject 'Potwierdzenie zamowienia nr: 1682'
Assert-True ($null -ne $psine -and $psine.orderNo -eq '1682') 'psine order no'
Assert-True ($psine.firstname -eq 'Marek' -and $psine.surname -eq 'Majewski') 'psine person name'
Assert-True ($psine.email -eq 'kontakt@psine.pl') 'psine email'
Assert-True ($psine.nip -eq '6572125912') 'psine NIP'
Assert-True ($psine.city -eq 'Kielce' -and $psine.zip -eq '25-019') 'psine city/zip'
Assert-True ($psine.street -match 'Karczowkowska') 'psine street'
Assert-True ($psine.companyRaw -match 'PSINE') 'psine company'

$psineQ = ConvertFrom-ShoperOrder -Body @"
Klient: Marek Majewski
E-mail: kontakt@psine.pl

> Dane zamawiajacego:
> >> Marek Majewski
> >> PSINE.PL Marek Majewski, 6572125912
> >> 25-019 Kielce
> >> ul.Karczowkowska 8A
"@ -Subject 'Re: Potwierdzenie zamowienia nr: 1682'
Assert-True ($psineQ.firstname -eq 'Marek' -and $psineQ.surname -eq 'Majewski') 'quoted psine person'
Assert-True ($psineQ.companyRaw -notmatch '^>') 'quoted company without >>'
Assert-True ((ConvertTo-NormalizedEmail 'mailto:biuro@bisek.net') -eq 'biuro@bisek.net') 'strip mailto:'
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($Failed -gt 0) {
    Write-Host "`nFAILED: $Failed" -ForegroundColor Red
    exit 1
}
Write-Host "`nALL TESTS PASSED" -ForegroundColor Green
exit 0
