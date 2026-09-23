function Read-HostDefault {
    param([string]$Prompt, [string]$Default = '')
    $hint = if ($Default -ne '') { $Default } else { '' }
    $value = Read-UiHost -Prompt $Prompt -Hint $hint
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

function Read-HostYesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $hint = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    $value = Read-UiHost -Prompt $Prompt -Hint $hint
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultYes }
    return $value.Trim() -match '^(y|yes|t|tak)$'
}

function Invoke-ConfigWizard {
    param(
        [string]$RepoRoot,
        [string]$ConfigPath,
        [string]$Email = ''
    )
    $shoper = Get-ShoperImapPreset
    Write-Host ''
    Write-Ui Section 'Poczta Shoper / Shoparena (stałe IMAP — bez wyboru innych dostawców):'
    Write-Ui Value ("  host={0}  port={1}  tls={2}" -f $shoper.Host, $shoper.Port, $shoper.Tls)
    Write-Ui Muted ("  {0}" -f $shoper.Note)

    if (-not $Email) {
        $Email = Read-UiHost -Prompt 'Adres e-mail skrzynki Shoper'
    }
    $Email = $Email.Trim()
    $cfg = New-AppConfigFromAnswers -Email $Email

    if (Test-Path -LiteralPath $ConfigPath) {
        $ow = Read-HostYesNo "Plik $(Split-Path $ConfigPath -Leaf) już istnieje. Nadpisać?" $true
        if (-not $ow) {
            Write-Ui Info 'Zostawiam istniejący config.json.'
            return (Read-AppConfig $ConfigPath)
        }
    }

    Save-AppConfig -Config $cfg -Path $ConfigPath
    Write-Host ''
    Write-Ui Ok "Zapisano $ConfigPath"
    Write-Ui Value ("IMAP {0}:{1} ({2})  user={3}" -f $cfg.imap.host, $cfg.imap.port, $cfg.imap.tls, $cfg.imap.user)
    Write-Ui Err 'Hasło NIE jest w pliku. Podasz je za chwilę albo ustaw IMAP_PASSWORD.'
    return $cfg
}

function Invoke-SelfTestChild {
    param([string]$RepoRoot)
    $st = Join-Path $RepoRoot 'tests\SelfTest.ps1'
    $exe = (Get-Process -Id $PID).Path
    if (-not $exe) {
        $exe = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell.exe' }
    }
    & $exe -NoProfile -ExecutionPolicy Bypass -File $st
    if ($LASTEXITCODE -ne 0) { throw "SelfTest nie przeszedł (kod $LASTEXITCODE). Napraw środowisko zanim ruszysz żywą skrzynkę." }
}

function Invoke-FetchPlanWizard {
    param(
        $Config,
        [string]$Password,
        [string]$RepoRoot,
        $FolderInfos
    )
    $scan = ConvertTo-FlatStringArray @($FolderInfos | Where-Object include | ForEach-Object { $_.name })
    if ($scan.Count -eq 0) { throw 'Brak folderów SCAN — sprawdź excludeNameRegex / folders.include.' }

    Write-Host ''
    Write-Ui Section ("Foldery SCAN: {0} (Sent/Trash itd. już pominięte)" -f $scan.Count)
    $i = 0
    foreach ($name in $scan) {
        $i++
        Write-Host ("  {0,3}." -f $i) -ForegroundColor Cyan -NoNewline
        Write-Host (" {0}" -f $name) -ForegroundColor White
    }

    $ordersOnly = [bool]$Config.orders.enabled -and -not [bool]$Config.signatures.enabled
    Write-Host ''
    if ($ordersOnly) {
        Write-Ui Accent 'Tryb: tylko potwierdzenia zamówień (stopy wyłączone).'
        Write-Ui Info 'Wybierz folder(y), w których leżą maile „Potwierdzenie zamówienia…”'
    }
    else {
        Write-Ui Accent 'Z wybranych folderów: potwierdzenia (szablon) + reszta korespondencji (stopy).'
        Write-Ui Info 'Wybierz foldery, w których u Ciebie leży poczta sklepu — nazwy zależą od sklepu.'
    }
    Write-Ui Muted 'Wybór: numery (1,3 albo 1-5)  |  * = wszystkie SCAN  |  dokładna nazwa folderu'
    Write-Ui Muted '(brak domyślnego folderu — musisz wybrać sam).'
    $chosen = @()
    while ($chosen.Count -eq 0) {
        $pickRaw = Read-HostDefault 'Które foldery pobrać' ''
        if ([string]::IsNullOrWhiteSpace($pickRaw)) {
            Write-Ui Warn 'Nic nie wybrano — podaj numer(y), nazwę albo *.'
            continue
        }
        $chosen = ConvertTo-FlatStringArray (ConvertFrom-FolderPickSelection -InputText $pickRaw -Candidates $scan)
        if ($chosen.Count -eq 0) {
            Write-Ui Warn 'Nie rozpoznano wyboru — spróbuj ponownie (np. 1 albo *).'
        }
    }

    Write-Host ''
    if ($ordersOnly) {
        Write-Ui Info ("Wybrano {0} folder(ów). Liczę maile z tematem potwierdzenia zamówienia…" -f $chosen.Count)
    }
    else {
        Write-Ui Info ("Wybrano {0} folder(ów). Sprawdzam liczbę wiadomości…" -f $chosen.Count)
    }
    $countRows = @(Get-ImapFolderMessageCounts -Config $Config -Password $Password -RepoRoot $RepoRoot -FolderNames $chosen -OrdersOnly:$ordersOnly)
    if ($countRows.Count -eq 1 -and $countRows[0] -is [System.Array]) {
        $countRows = @($countRows[0])
    }
    $sum = 0
    $fail = 0
    foreach ($c in $countRows) {
        if ($c.count -lt 0) {
            $fail++
            $err = if ($c.error) { "  ($($c.error))" } else { '' }
            Write-UiFolderCountLine -Name ([string]$c.name) -CountLabel '?' -Extra $err -CountColor Red
        }
        else {
            if ($c.count -gt 0) { $sum += $c.count }
            $oc = -1
            if (-not $ordersOnly -and $c.PSObject.Properties.Name -contains 'orderCount' -and [int]$c.orderCount -ge 0) {
                $oc = [int]$c.orderCount
            }
            Write-UiFolderCountLine -Name ([string]$c.name) -CountLabel ([string]$c.count) -OrderCount $oc
        }
    }
    Write-Host "`tSuma (znane): " -ForegroundColor White -NoNewline
    Write-Host $sum -ForegroundColor Cyan -NoNewline
    Write-Host '  |  folderów bez licznika: ' -ForegroundColor White -NoNewline
    Write-Host $fail -ForegroundColor $(if ($fail -gt 0) { 'Yellow' } else { 'White' })

    $defMax = 0
    if ($Config.imap.PSObject.Properties.Name -contains 'maxMessagesPerFolder') {
        $defMax = [int]$Config.imap.maxMessagesPerFolder
    }
    $defHint = if ($defMax -gt 0) { [string]$defMax } else { 'wszystkie' }
    Write-Host ''
    Write-Ui Info 'Limit na folder (najnowsze N; Enter = bez limitu / wartość z config).'
    $maxRaw = Read-HostDefault 'Ile wiadomości na folder' $defHint
    $max = 0
    if ($maxRaw -match '^(?i)(wszystkie|all|\*)$' -or [string]::IsNullOrWhiteSpace($maxRaw)) {
        $max = 0
    }
    elseif ($maxRaw -eq $defHint -and $defMax -gt 0) {
        $max = $defMax
    }
    else {
        $parsed = 0
        if (-not [int]::TryParse($maxRaw, [ref]$parsed) -or $parsed -lt 0) {
            throw "Limit musi być liczbą >= 0 (podano: $maxRaw)."
        }
        $max = $parsed
    }

    Write-Host ''
    Write-Ui Section 'Plan pobierania:'
    foreach ($c in $countRows) {
        $will = $c.count
        if ($will -lt 0) { $willLabel = '?' }
        elseif ($max -gt 0 -and $will -gt $max) { $willLabel = "$max z $($c.count)" }
        else { $willLabel = [string]$will }
        Write-Host "`t• " -ForegroundColor Cyan -NoNewline
        Write-Host ([string]$c.name) -ForegroundColor White -NoNewline
        Write-Host ' → ' -ForegroundColor White -NoNewline
        Write-Host $willLabel -ForegroundColor Cyan
    }

    return [PSCustomObject]@{
        Folders              = $chosen
        MaxMessagesPerFolder = $max
        Counts               = $countRows
    }
}

function Invoke-SetupWizard {
    param(
        [string]$RepoRoot,
        [string]$ConfigPath,
        [string]$Email = ''
    )
    Write-Ui Title 'MailToContacts — Shoper/Shoparena (e-mail → config → foldery → run)'
    Write-Ui Muted "Katalog: $RepoRoot"

    if (Read-HostYesNo 'Uruchomić SelfTest (bez sieci, zalecane)?' $true) {
        Invoke-SelfTestChild $RepoRoot
    }

    $cfg = Invoke-ConfigWizard -RepoRoot $RepoRoot -ConfigPath $ConfigPath -Email $Email

    Write-Host ''
    Write-Ui Section 'Źródła książki (warstwy):'
    Write-Ui Value '  1. Potwierdzenia zamówień Shoper — szablon „Dane zamawiającego” (pewne).'
    Write-Ui Value '  2. Reszta korespondencji — stopy, reguły.'
    Write-Ui Muted '  3. Ollama — tylko gdy reguły nie dają rady (słabe trafienia).'
    $cfg.signatures.enabled = Read-HostYesNo 'Szukać kontaktów też w stopkach zwykłych maili (nie tylko zamówienia)?' $true
    if ($cfg.signatures.enabled) {
        $cfg.signatures.useOllama = Read-HostYesNo 'Użyć lokalnej Ollamy do słabych stopek? (maile zostają na tym PC)' $false
        if ($cfg.signatures.useOllama) {
            if (Ensure-OllamaReady -Config $cfg) {
                Write-Ui Ok 'Ollama gotowa do tego uruchomienia.'
            }
            else {
                $cfg.signatures.useOllama = $false
                Write-Ui Muted 'Ollama wyłączona na ten raz. Słabe stopy lądują w ai_queue.jsonl. Książka i tak powstanie.'
            }
        }
        else {
            Write-Ui Muted 'Ollama wyłączona. Słabe stopy lądują w ai_queue.jsonl (bez modelu).'
        }
    }
    else {
        $cfg.signatures.useOllama = $false
        Write-Ui Info 'Tylko potwierdzenia zamówień — stopy pominięte.'
    }
    Save-AppConfig -Config $cfg -Path $ConfigPath

    Ensure-MailKit $RepoRoot

    if (-not $cfg.imap.user -or -not $cfg.imap.host) {
        throw 'config.json bez imap.user / imap.host — przerwij i uruchom kreator jeszcze raz.'
    }

    $pass = Get-ImapPassword $cfg.imap.user
    Write-Host ''
    Write-Ui Section 'LIST folderów IMAP…'
    $infos = Invoke-ImapDiscover -Config $cfg -Password $pass -RepoRoot $RepoRoot
    Write-UiFolderDecision $infos

    $plan = Invoke-FetchPlanWizard -Config $cfg -Password $pass -RepoRoot $RepoRoot -FolderInfos $infos

    if (-not (Read-HostYesNo 'Start run (pobrać wybrane maile i zbudować contacts.vcf)?' $true)) {
        Write-Ui Info 'Koniec kreatora. Później: powershell -File .\src\MailToContacts.ps1 run'
        return
    }

    Write-Host ''
    Write-Ui Section 'Pobieram wiadomości…'
    $folders = ConvertTo-FlatStringArray $plan.Folders
    $result = Invoke-ImapLiveRun -Config $cfg -Password $pass -RepoRoot $RepoRoot `
        -Folders $folders -MaxMessagesPerFolder ([int]$plan.MaxMessagesPerFolder) -ShowProgress
    Write-Host ''
    Write-Host 'contacts=' -ForegroundColor White -NoNewline
    Write-Host $result.Book.contactCount -ForegroundColor Green -NoNewline
    Write-Host ' -> ' -ForegroundColor White -NoNewline
    Write-Host $result.RunDir -ForegroundColor White
    Write-Host 'VCF: ' -ForegroundColor White -NoNewline
    Write-Host (Join-Path $result.RunDir 'contacts.vcf') -ForegroundColor Green
}
