function ConvertFrom-FetchedOrderFiles {
    param([string]$FetchedDir, [string[]]$SelfEmails)
    $orders = @()
    $jsonl = Join-Path $FetchedDir 'orders.jsonl'
    if (Test-Path -LiteralPath $jsonl) {
        foreach ($rec in (Read-Jsonl $jsonl)) {
            $parsed = ConvertFrom-ShoperOrder -Body $rec.body -Subject $rec.subject -Folder $rec.folder -Uid $rec.uid -SelfEmails $SelfEmails
            if ($parsed) { $orders += $parsed }
        }
        return @($orders)
    }
    Get-ChildItem -LiteralPath $FetchedDir -Filter 'order-*.txt' | ForEach-Object {
        $body = [IO.File]::ReadAllText($_.FullName, [Text.UTF8Encoding]::new($false))
        $no = if ($_.BaseName -match '(\d+)') { $Matches[1] } else { '' }
        $subject = if ($no) { "Potwierdzenie zamówienia nr: $no" } else { $_.BaseName }
        $parsed = ConvertFrom-ShoperOrder -Body $body -Subject $subject -Folder 'INBOX' -Uid $_.BaseName -SelfEmails $SelfEmails
        if ($parsed) { $orders += $parsed }
    }
    return @($orders)
}

function ConvertFrom-FetchedMessages {
    param([string]$FetchedDir, [string[]]$SelfEmails)
    $messages = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $jsonl = Join-Path $FetchedDir 'messages.jsonl'
    if (Test-Path -LiteralPath $jsonl) {
        foreach ($rec in (Read-Jsonl $jsonl)) {
            $mid = [string]($(if ($rec.messageId) { $rec.messageId } else { $rec.uid }))
            if ($mid -and -not $seen.Add($mid)) { continue }
            $from = ConvertTo-NormalizedEmail $rec.fromEmail $SelfEmails
            if (-not $from -and $rec.fromEmail) { continue }
            $full = if ($rec.bodyFull) { [string]$rec.bodyFull } else { [string]$rec.body }
            $messages += [PSCustomObject]@{
                    folder      = $(if ($rec.folder) { $rec.folder } else { 'INBOX' })
                    folderKind  = $(if ($rec.folderKind) { $rec.folderKind } else { 'inbox' })
                    folderLabel = [string]$rec.folderLabel
                    uid         = [string]$rec.uid
                    messageId   = $mid
                    date        = [string]$rec.date
                    subject     = [string]$rec.subject
                    fromName    = [string]$rec.fromName
                    fromEmail   = $(if ($from) { $from } else { [string]$rec.fromEmail })
                    toRaw       = [string]$rec.toRaw
                    bodyFull    = $full
                    body        = $(if ($rec.body) { [string]$rec.body } else { Remove-QuotedHistory $full })
            }
        }
        return @($messages)
    }
    $map = @(
        @{ File = 'mail-company-signature.txt'; From = 'anna.nowak@example.com'; Name = 'Anna Nowak'; Subject = 'Wycena 50 szt.'; Uid = '201' }
        @{ File = 'mail-person-signature.txt'; From = 'piotr.zielinski@example.com'; Name = 'Piotr Zieliński'; Subject = 'Zamówienie detaliczne'; Uid = '202' }
        @{ File = 'mail-quoted-thread.txt'; From = 'jan.kowalski@example.com'; Name = 'Jan Kowalski'; Subject = 'Re: adres wysyłki'; Uid = '203' }
    )
    foreach ($item in $map) {
        $path = Join-Path $FetchedDir $item.File
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $full = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false))
        $messages += [PSCustomObject]@{
                folder = 'INBOX'; folderKind = 'inbox'; folderLabel = ''
                uid = $item.Uid; messageId = "<msg-$($item.Uid)@example.com>"
                date = ''; subject = $item.Subject
                fromName = $item.Name; fromEmail = $item.From; toRaw = 'sklep@example.com'
                bodyFull = $full; body = (Remove-QuotedHistory $full)
            }
    }
    return @($messages)
}

function Invoke-OfflinePipeline {
    param(
        [string]$FetchedDir,
        [string]$OutDir,
        $Config
    )
    if (-not $Config) { $Config = Get-DefaultConfig }
    $selfEmails = @($Config.self.emails)
    $selfPhones = @($Config.self.phones)
    [IO.Directory]::CreateDirectory($OutDir) | Out-Null

    $orders = @(ConvertFrom-FetchedOrderFiles $FetchedDir $selfEmails)
    $messages = @()
    if ($Config.signatures.enabled) {
        $messages = @(ConvertFrom-FetchedMessages $FetchedDir $selfEmails)
    }
    $companies = @(Get-CompaniesFromOrders $orders)
    $book = ConvertTo-ContactsFromOrders $orders $companies
    $hits = @{ Rules = @(); Queue = @() }
    $queue = @()
    if ($Config.signatures.enabled) {
        $hits = Get-SignatureHits -Messages $messages -SelfEmails $selfEmails -SelfPhones $selfPhones -AiThreshold ([double]$Config.signatures.aiConfidenceBelow)
        $queue = @($hits.Queue)
        if ($Config.signatures.useOllama) {
            $ollamaUrl = [string]$Config.ollama.url
            if (-not (Test-OllamaAvailable -Url $ollamaUrl)) {
                Write-Warning ("Ollama nie odpowiada pod {0} — słabe stopy zostają w ai_queue.jsonl (uruchom daemon albo wyłącz useOllama w kreatorze)." -f $ollamaUrl)
            }
            else {
                $filled = foreach ($h in $queue) {
                    Invoke-OllamaExtract -Hit $h -Url $ollamaUrl -Model $Config.ollama.model
                }
                $queue = @($filled)
            }
        }
        else {
            foreach ($h in $queue) {
                $g = Remove-HallucinatedFields $h.extracted $h.block
                $h.extracted = $g.Extracted
                $h.droppedFields = @($g.Dropped)
            }
        }
        $book = Merge-SignatureHits -Book $book -Hits (@($hits.Rules) + $queue) -SelfEmails $selfEmails
    }
    Write-PipelineOutputs -OutDir $OutDir -Orders $orders -Companies $companies -Book $book -Messages $messages -Rules $hits.Rules -Queue $queue
    return $book
}

function Write-PipelineOutputs {
    param($OutDir, $Orders, $Companies, $Book, $Messages, $Rules, $Queue)
    ConvertTo-JsonFile -Object @($Orders) -Path (Join-Path $OutDir 'orders_raw.json')
    ConvertTo-JsonFile -Object @($Companies) -Path (Join-Path $OutDir 'companies_by_nip.json')
    ConvertTo-JsonFile -Object $Book -Path (Join-Path $OutDir 'contacts_unified.json')
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $OutDir 'contacts.vcf'), (ConvertTo-ContactBookVcf $Book), $utf8)
    Export-ContactBookCsv -Book $Book -Path (Join-Path $OutDir 'contacts.csv')
    Write-Jsonl -Rows $Messages -Path (Join-Path $OutDir 'messages_raw.jsonl')
    Write-Jsonl -Rows $Rules -Path (Join-Path $OutDir 'extracted_rules.jsonl')
    Write-Jsonl -Rows $Queue -Path (Join-Path $OutDir 'ai_queue.jsonl')
    $report = @"
orders=$($Orders.Count)
contacts=$($Book.contactCount)
messages=$($Messages.Count)
signatures_rules=$(@($Rules).Count)
signatures_ai_queue=$(@($Queue).Count)
"@
    [IO.File]::WriteAllText((Join-Path $OutDir 'RAPORT.txt'), $report, $utf8)
}

function Get-ImapRunDirectory {
    param($Config, [string]$RepoRoot)
    $rel = [string]$Config.output.dir
    if ([IO.Path]::IsPathRooted($rel)) { $outDir = $rel }
    else { $outDir = Join-Path $RepoRoot ($rel.TrimStart('.', '\', '/')) }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $runDir = Join-Path $outDir "run_$stamp"
    [IO.Directory]::CreateDirectory($runDir) | Out-Null
    return $runDir
}

function Format-ImapFolderDecision {
    param($Infos)
    foreach ($i in @($Infos)) {
        $flag = if ($i.include) { 'SCAN' } else { 'skip' }
        '{0,-4}  {1}  ({2})' -f $flag, $i.name, $i.reason
    }
}

function Invoke-ImapDiscover {
    param($Config, [string]$Password, [string]$RepoRoot)
    $client = Connect-ImapMailKit -Config $Config -Password $Password -RepoRoot $RepoRoot
    try {
        $listed = Get-ImapFolderNames $client
        $names = @($listed | ForEach-Object { $_.name })
        return @(Select-ImapFolders -Names $names -Include @($Config.folders.include) -ExcludeRegex $Config.folders.excludeNameRegex)
    }
    finally {
        if ($client.IsConnected) { $client.Disconnect($true) }
        $client.Dispose()
    }
}

function Invoke-ImapLiveRun {
    param(
        $Config,
        [string]$Password,
        [string]$RepoRoot,
        [string]$RunDir = '',
        $Folders = @(),
        [int]$MaxMessagesPerFolder = -1,
        [switch]$ShowProgress
    )
    if (-not $RunDir) { $RunDir = Get-ImapRunDirectory -Config $Config -RepoRoot $RepoRoot }
    $folderInfos = Invoke-ImapDiscover -Config $Config -Password $Password -RepoRoot $RepoRoot
    $scan = ConvertTo-FlatStringArray @($folderInfos | Where-Object include | ForEach-Object { $_.name })
    if ($Folders -and @($Folders).Count -gt 0) {
        $want = ConvertTo-FlatStringArray $Folders
        $wantLower = @($want | ForEach-Object { $_.ToLowerInvariant() })
        $scan = ConvertTo-FlatStringArray @($scan | Where-Object { $wantLower -contains $_.ToLowerInvariant() })
        if ($scan.Count -eq 0) { throw 'Żaden z wybranych folderów nie jest na liście SCAN (Sent/Trash są pomijane).' }
    }
    $max = $MaxMessagesPerFolder
    if ($max -lt 0) {
        if ($Config.imap.PSObject.Properties.Name -contains 'maxMessagesPerFolder') {
            $max = [int]$Config.imap.maxMessagesPerFolder
        }
        else { $max = 0 }
    }
    $show = [bool]$ShowProgress
    if (-not $PSBoundParameters.ContainsKey('ShowProgress')) { $show = $true }

    $counts = @()
    $overallTotal = 0
    $ordersOnly = [bool]$Config.orders.enabled -and -not [bool]$Config.signatures.enabled
    if ($show) {
        if ($ordersOnly) {
            Write-Ui Accent 'Tryb: tylko potwierdzenia zamówień (stopy wyłączone).'
            Write-Ui Info 'Szukam maili z tematem „Potwierdzenie zamówienia…” w wybranych folderach…'
        }
        else {
            Write-Ui Accent 'Limit = tyle najnowszych maili. W tej paczce: potwierdzenia (jeśli są) i stopki. Ollama tylko przy niepewnej stopce.'
            Write-Ui Info 'Sprawdzam liczbę wiadomości w wybranych folderach…'
        }
        $counts = @(Get-ImapFolderMessageCounts -Config $Config -Password $Password -RepoRoot $RepoRoot -FolderNames $scan -OrdersOnly:$ordersOnly)
        if ($counts.Count -eq 1 -and $counts[0] -is [System.Array]) { $counts = @($counts[0]) }
        foreach ($c in $counts) {
            $n = [int]$c.count
            if ($n -lt 0) { continue }
            if ($max -gt 0 -and $n -gt $max) { $n = $max }
            $overallTotal += $n
            $lim = if ($max -gt 0) { " (limit $max)" } else { '' }
            $oc = -1
            if (-not $ordersOnly -and $c.PSObject.Properties.Name -contains 'orderCount' -and [int]$c.orderCount -ge 0) {
                $oc = [int]$c.orderCount
            }
            Write-UiFolderCountLine -Name $c.name -CountLabel ("{0} wiadomości" -f $c.count) -OrderCount $oc -Extra $lim
        }
        Write-Host "`tDo pobrania łącznie ~" -ForegroundColor White -NoNewline
        Write-Host $overallTotal -ForegroundColor Cyan -NoNewline
        Write-Host (" wiadomości z {0} folderów." -f $scan.Count) -ForegroundColor White
        Write-Host ''
    }

    $self = Get-NormalizedEmailList $Config.self.emails
    $selfPhones = ConvertTo-FlatStringArray $Config.self.phones
    $orders = New-Object System.Collections.Generic.List[object]
    $messages = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $fi = 0
    $fc = $scan.Count
    $overallBase = 0
    foreach ($folder in $scan) {
        $fi++
        $expected = 0
        $hit = @($counts | Where-Object { $_.name -eq $folder })
        if ($hit.Count -gt 0 -and [int]$hit[0].count -ge 0) {
            $expected = [int]$hit[0].count
            if ($max -gt 0 -and $expected -gt $max) { $expected = $max }
        }
        if ($show) {
            Write-Host ''
            Write-Host ("Folder {0}/{1}: " -f $fi, $fc) -ForegroundColor Cyan -NoNewline
            Write-Host $folder -ForegroundColor White
        }
        $rawRows = Get-ImapFolderMessages -Config $Config -Password $Password -FolderName $folder -RepoRoot $RepoRoot `
            -MaxMessages $max -ShowProgress:$show -OrdersOnly:$ordersOnly `
            -FolderIndex $fi -FolderCount $fc -OverallBase $overallBase -OverallTotal $overallTotal
        $rows = Get-NormalizedMessageRows $rawRows
        $overallBase += $expected
        $user = ([string]$Config.imap.user).ToLowerInvariant()
        $rowCount = @($rows).Count
        if ($show -and $rowCount -gt 0) {
            Write-Host ("  → analizuję {0} wiadomości…" -f $rowCount) -ForegroundColor White
        }
        $ri = 0
        foreach ($m in $rows) {
            $ri++
            if ($show -and $rowCount -gt 40 -and ($ri % 25 -eq 0 -or $ri -eq $rowCount)) {
                $padded = ("`r  → analiza {0}/{1}" -f $ri, $rowCount).PadRight(60)
                Write-Host $padded -ForegroundColor DarkGray -NoNewline
                if ($ri -eq $rowCount) { Write-Host '' }
            }
            $mid = [string]$m.messageId
            if ($mid -and -not $seen.Add($mid)) { continue }
            $fromSelf = ($m.fromEmail -eq $user -or $self -contains $m.fromEmail)
            $parsed = $null
            if ($Config.orders.enabled) {
                $parsed = ConvertFrom-ShoperOrder -Body $m.bodyFull -Subject $m.subject -Folder $m.folder -Uid $m.uid -SelfEmails $self
                if ($parsed) { [void]$orders.Add($parsed); continue }
            }
            if ($fromSelf) { continue }
            if ($Config.signatures.enabled) { [void]$messages.Add($m) }
        }
    }
    if ($show -and $Config.orders.enabled -and $orders.Count -eq 0) {
        if ($max -gt 0) {
            Write-Warning ("Nie znaleziono potwierdzeń zamówień w tych {0} najnowszych mailach. Limit nie sięga starszych wiadomości." -f $max)
        }
        else {
            Write-Warning 'Nie znaleziono potwierdzeń zamówień w wybranych folderach - książka oprze się na stopkach zwykłych maili (jeśli włączone).'
        }
    }
    $orderArr = @($orders.ToArray())
    $msgArr = @($messages.ToArray())

    $companies = @(Get-CompaniesFromOrders $orderArr)
    $book = ConvertTo-ContactsFromOrders $orderArr $companies
    $hits = @{ Rules = @(); Queue = @() }
    $queue = @()
    if ($Config.signatures.enabled) {
        $hits = Get-SignatureHits -Messages $msgArr -SelfEmails $self -SelfPhones $selfPhones -AiThreshold ([double]$Config.signatures.aiConfidenceBelow)
        $queue = @($hits.Queue)
        if ($Config.signatures.useOllama) {
            $ollamaUrl = [string]$Config.ollama.url
            if (-not (Test-OllamaAvailable -Url $ollamaUrl)) {
                $exe = Get-OllamaExecutable
                if ($exe) {
                    Write-Host '  Ollama nie odpowiada. Próbuję ją uruchomić (program musi działać, nie wystarczy sama instalacja)...' -ForegroundColor Yellow
                    [void](Start-OllamaDaemon -Executable $exe -Url $ollamaUrl)
                }
            }
            if (-not (Test-OllamaAvailable -Url $ollamaUrl)) {
                if (Get-OllamaExecutable) {
                    Write-Warning ("Ollama jest zainstalowana, ale nie działa pod {0}. Włącz program Ollama z menu Start (ikona przy zegarze), potem uruchom skrypt ponownie. Słabe stopy zostają w ai_queue.jsonl." -f $ollamaUrl)
                }
                else {
                    Write-Warning ("Ollama nie jest zainstalowana albo nie odpowiada pod {0}. Słabe stopy zostają w ai_queue.jsonl. W kreatorze możesz ją doinstalować (winget) i pobrać model." -f $ollamaUrl)
                }
            }
            elseif (-not (Test-OllamaModelPresent -Url $ollamaUrl -Model $Config.ollama.model)) {
                Write-Warning ("Ollama działa, ale brak modelu {0}. W kreatorze wybierz pobranie albo: ollama pull {0}. Słabe stopy zostają w ai_queue.jsonl." -f $Config.ollama.model)
            }
            else {
                $qi = 0
                $qc = @($queue).Count
                if ($show -and $qc -gt 0) {
                    Write-Host ("  → Ollama: {0} słabych stopek…" -f $qc) -ForegroundColor White
                }
                $filled = foreach ($h in $queue) {
                    $qi++
                    if ($show -and $qc -gt 0) {
                        Write-Host ("`r  → Ollama {0}/{1}" -f $qi, $qc) -ForegroundColor DarkGray -NoNewline
                    }
                    Invoke-OllamaExtract -Hit $h -Url $ollamaUrl -Model $Config.ollama.model
                }
                if ($show -and $qc -gt 0) { Write-Host '' }
                $queue = @($filled)
            }
        }
        $book = Merge-SignatureHits -Book $book -Hits (@($hits.Rules) + $queue) -SelfEmails $self
    }
    Write-PipelineOutputs -OutDir $RunDir -Orders $orderArr -Companies $companies -Book $book -Messages $msgArr -Rules $hits.Rules -Queue $queue
    return [PSCustomObject]@{
        Book                 = $book
        RunDir               = $RunDir
        FolderInfos          = $folderInfos
        FoldersFetched       = $scan
        MaxMessagesPerFolder = $max
    }
}
