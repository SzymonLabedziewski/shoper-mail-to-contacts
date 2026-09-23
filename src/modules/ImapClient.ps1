# IMAP via MailKit 4.17 (not a hand-rolled socket). One ImapClient is NOT thread-safe —
# v1 fetches folders sequentially, each with its own Connect (AGENTS.md / docs/ARCHITECTURE.md).

function Get-MailKitLibDir {
    param([string]$RepoRoot)
    return (Join-Path $RepoRoot 'lib\mailkit')
}

function Test-MailKitLoaded {
    try {
        $null = [MailKit.Net.Imap.ImapClient]
        return $true
    }
    catch { return $false }
}

function Test-MailKitInstalled {
    param([string]$RepoRoot)
    $dir = Get-MailKitLibDir $RepoRoot
    foreach ($dll in @('BouncyCastle.Cryptography.dll', 'MimeKit.dll', 'MailKit.dll')) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir $dll))) { return $false }
    }
    return $true
}

function Get-MailKitLoadOrder {
    param([string]$Dir)
    $preferred = @(
        'System.ValueTuple.dll',
        'System.Numerics.Vectors.dll',
        'System.Buffers.dll',
        'System.Runtime.CompilerServices.Unsafe.dll',
        'System.Memory.dll',
        'System.Threading.Tasks.Extensions.dll',
        'System.Text.Encoding.CodePages.dll',
        'System.Formats.Asn1.dll',
        'System.Security.Cryptography.Pkcs.dll',
        'BouncyCastle.Cryptography.dll',
        'MimeKit.dll',
        'MailKit.dll'
    )
    $present = @{}
    Get-ChildItem -LiteralPath $Dir -Filter '*.dll' -ErrorAction SilentlyContinue | ForEach-Object {
        $present[$_.Name] = $_.FullName
    }
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($name in $preferred) {
        if ($present.ContainsKey($name)) {
            $ordered.Add($present[$name])
            $present.Remove($name)
        }
    }
    foreach ($name in ($present.Keys | Sort-Object)) {
        $ordered.Add($present[$name])
    }
    return @($ordered)
}

function Register-MailKitAssemblyResolve {
    param([string]$Dir)
    $script:MailKitLibPath = $Dir
    if ($script:MailKitResolveRegistered) { return }
    $handler = {
        param($sender, $e)
        try {
            if (-not $script:MailKitLibPath) { return $null }
            $an = New-Object System.Reflection.AssemblyName $e.Name
            if ($an.Name -match '\.resources$') { return $null }
            $candidate = Join-Path $script:MailKitLibPath ($an.Name + '.dll')
            if (Test-Path -LiteralPath $candidate) {
                return [System.Reflection.Assembly]::LoadFrom($candidate)
            }
        }
        catch { }
        return $null
    }
    [AppDomain]::CurrentDomain.add_AssemblyResolve($handler)
    $script:MailKitResolveRegistered = $true
}

function Import-MailKit {
    param([string]$RepoRoot)
    if (Test-MailKitLoaded) { return }
    $dir = Get-MailKitLibDir $RepoRoot
    Register-MailKitAssemblyResolve $dir
    if (-not (Test-MailKitInstalled $RepoRoot)) {
        throw @"
MailKit nie jest zainstalowany ($dir).
Uruchom:  .\src\MailToContacts.ps1 install-mailkit
Albo kreator:  powershell -File .\Uruchom.ps1
Tryb demo/selftest NIE wymaga MailKit (czyta samples/).
"@
    }
    $paths = Get-MailKitLoadOrder $dir
    foreach ($path in $paths) {
        try {
            Add-Type -Path $path
        }
        catch {
            $msg = [string]$_.Exception.Message
            if ($msg -match 'already exists|already loaded|został już załadowany|został już dodany') { continue }
            $detail = $msg
            $loaderMsgs = @()
            $walk = $_.Exception
            while ($walk) {
                $hasLoader = $false
                try { if ($walk.LoaderExceptions) { $hasLoader = $true } } catch { $hasLoader = $false }
                if ($hasLoader) {
                    foreach ($le in @($walk.LoaderExceptions)) {
                        if ($le) { $loaderMsgs += [string]$le.Message }
                    }
                }
                $walk = $walk.InnerException
            }
            if ($loaderMsgs.Count -gt 0) {
                $detail = "$detail`nLoaderExceptions:`n  $($loaderMsgs -join "`n  ")"
            }
            $hint = ''
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $hint = @"

Windows PowerShell 5.1 ładuje MailKit z lib/net48 (nigdy net8.0).
1. Zamknij to okno PowerShell (stare DLL-e zostają w procesie).
2. powershell -File .\src\MailToContacts.ps1 install-mailkit
3. Ponów discover / Uruchom.ps1
Albo zainstaluj PowerShell 7+ (pwsh).
"@
            }
            throw "Nie udało się załadować $(Split-Path $path -Leaf): $detail$hint"
        }
    }
    if (-not (Test-MailKitLoaded)) {
        throw 'MailKit.dll załadowany, ale typ MailKit.Net.Imap.ImapClient jest niedostępny.'
    }
}

function Install-MailKitLibs {
    param([string]$RepoRoot)
    $installer = Join-Path $RepoRoot 'src\scripts\Install-MailKit.ps1'
    if (-not (Test-Path -LiteralPath $installer)) { throw "Brak $installer" }
    & $installer -RepoRoot $RepoRoot
}

function Test-MailKitNeedsReinstall {
    param([string]$RepoRoot)
    if (-not (Test-MailKitInstalled $RepoRoot)) { return $true }
    $tfmFile = Join-Path (Get-MailKitLibDir $RepoRoot) 'tfm.txt'
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if (-not (Test-Path -LiteralPath $tfmFile)) { return $true }
        $mark = [IO.File]::ReadAllText($tfmFile)
        if ($mark -notmatch 'ps51|netstandard|netfx') { return $true }
    }
    return $false
}

function Ensure-MailKit {
    param([string]$RepoRoot)
    if (Test-MailKitNeedsReinstall $RepoRoot) {
        Write-Host 'Instaluję MailKit (DLL-e dopasowane do tej wersji PowerShell)…'
        Install-MailKitLibs $RepoRoot
    }
    try {
        Import-MailKit $RepoRoot
    }
    catch {
        Write-Warning 'MailKit nie ładuje się — ponawiam instalację (net48 dla Windows PowerShell 5.1).'
        Install-MailKitLibs $RepoRoot
        Import-MailKit $RepoRoot
    }
}

function Connect-ImapMailKit {
    param(
        $Config,
        [string]$Password,
        [string]$RepoRoot
    )
    Import-MailKit $RepoRoot
    $client = [MailKit.Net.Imap.ImapClient]::new()
    if ($Config.imap.insecureSkipCert) {
        $client.ServerCertificateValidationCallback = { $true }
        Write-Warning 'imap.insecureSkipCert=true — certyfikat TLS NIE jest weryfikowany.'
    }
    $tls = [string]$Config.imap.tls
    $opt = if ($tls -eq 'starttls') {
        [MailKit.Security.SecureSocketOptions]::StartTls
    }
    else {
        [MailKit.Security.SecureSocketOptions]::SslOnConnect
    }
    try {
        $client.Connect([string]$Config.imap.host, [int]$Config.imap.port, $opt)
    }
    catch {
        $client.Dispose()
        throw ("Nie łączy z IMAP {0}:{1} ({2}): {3}" -f $Config.imap.host, $Config.imap.port, $tls, $_.Exception.Message)
    }
    if ([string]::IsNullOrEmpty($Password)) {
        $client.Dispose()
        throw 'Puste hasło IMAP — wpisz hasło albo ustaw zmienną IMAP_PASSWORD.'
    }
    try {
        $client.Authenticate([string]$Config.imap.user, $Password)
    }
    catch {
        $user = [string]$Config.imap.user
        $client.Dispose()
        throw @"
Logowanie IMAP nieudane dla $user na $($Config.imap.host):$($Config.imap.port) ($tls).
Sprawdź:
  • hasło (panel Shoper / Shoparena → poczta — często osobne hasło IMAP, nie hasło do panelu)
  • adres e-mail (user) i host
  • czy IMAP jest włączony w skrzynce
Szczegół serwera: $($_.Exception.Message)
"@
    }
    return $client
}

function Get-ImapSpecialUseName {
    param($Folder)
    try {
        $attrs = $Folder.Attributes.ToString()
        return $attrs
    }
    catch { return "" }
}

function Get-ImapFolderNames {
    <#
      Recursively list ALL folders under the personal namespace AND under INBOX.
      Flat mailboxes (only INBOX) and deep trees (INBOX.FIRMY.X, INBOX/Klienci/…) both work.
    #>
    param($Client)
    $names = New-Object System.Collections.Generic.List[object]
    $names.Add([PSCustomObject]@{ name = $Client.Inbox.FullName; specialUse = Get-ImapSpecialUseName $Client.Inbox })
    try {
        foreach ($child in $Client.Inbox.GetSubfolders($false)) {
            Get-ImapFolderNamesRecursive $child $names
        }
    }
    catch { }
    try {
        $personal = $Client.GetFolder($Client.PersonalNamespaces[0])
        foreach ($f in $personal.GetSubfolders($false)) {
            Get-ImapFolderNamesRecursive $f $names
        }
    }
    catch { }
    return @($names | Sort-Object name -Unique)
}

function Get-ImapFolderNamesRecursive {
    param($Folder, $Acc)
    $Acc.Add([PSCustomObject]@{ name = $Folder.FullName; specialUse = Get-ImapSpecialUseName $Folder })
    try {
        foreach ($child in $Folder.GetSubfolders($false)) {
            Get-ImapFolderNamesRecursive $child $Acc
        }
    }
    catch { }
}

function ConvertFrom-MimeMessage {
    param($Message, [string]$Folder)
    $fromEmail = ""
    $fromName = ""
    if ($Message.From -and $Message.From.Count -gt 0) {
        $mb = $Message.From[0]
        $fromEmail = ([string]$mb.Address).ToLowerInvariant()
        $fromName = [string]$mb.Name
    }
    $text = ""
    if ($Message.TextBody) { $text = [string]$Message.TextBody }
    elseif ($Message.HtmlBody) { $text = ConvertFrom-HtmlToPlain $Message.HtmlBody }
    $mid = [string]$Message.MessageId
    return [PSCustomObject]@{
        folder      = $Folder
        folderKind  = 'inbox'
        folderLabel = ""
        uid         = ""
        messageId   = $mid
        date        = [string]$Message.Date
        subject     = [string]$Message.Subject
        fromName    = $fromName
        fromEmail   = $fromEmail
        toRaw       = [string]$Message.To
        bodyFull    = $text
        body        = (Remove-QuotedHistory $text)
    }
}

function Write-ImapFetchProgress {
    param(
        [string]$FolderName,
        [int]$Done,
        [int]$Total,
        [int]$FolderIndex = 0,
        [int]$FolderCount = 0,
        [int]$OverallDone = 0,
        [int]$OverallTotal = 0,
        [switch]$Finish
    )
    $pct = if ($Total -gt 0) { [int](100.0 * $Done / $Total) } else { 100 }
    $line = "[{0}] {1}/{2} ({3}%)" -f $FolderName, $Done, $Total, $pct
    if ($FolderCount -gt 0 -and $FolderIndex -gt 0) {
        $line = "folder {0}/{1}  {2}" -f $FolderIndex, $FolderCount, $line
    }
    if ($OverallTotal -gt 0) {
        $op = [int](100.0 * $OverallDone / $OverallTotal)
        $line = "{0}  |  łącznie {1}/{2} ({3}%)" -f $line, $OverallDone, $OverallTotal, $op
    }
    # `r + PadRight czyści poprzednią linię; Finish kończy Enterem (bez podwójnego tekstu).
    $padded = "`r" + $line.PadRight(120)
    if ($Finish) {
        Write-Host $padded -ForegroundColor Cyan
    }
    else {
        Write-Host $padded -ForegroundColor Cyan -NoNewline
    }
}

function Get-ShoperOrderSearchHints {
    @(
        'Potwierdzenie zamówienia',
        'Potwierdzenie zamowienia',
        'zamówienia nr',
        'zamowienia nr'
    )
}

function Get-ImapOrderSearchQuery {
    $hints = Get-ShoperOrderSearchHints
    $query = $null
    foreach ($h in $hints) {
        $q = [MailKit.Search.SearchQuery]::SubjectContains($h)
        if ($null -eq $query) { $query = $q }
        else { $query = [MailKit.Search.SearchQuery]::Or($query, $q) }
    }
    return $query
}

function Get-ImapFolderMessageCounts {
    param(
        $Config,
        [string]$Password,
        [string]$RepoRoot,
        $FolderNames,
        [switch]$OrdersOnly
    )
    $names = ConvertTo-FlatStringArray $FolderNames
    if ($names.Count -eq 0) { return , @() }
    $client = Connect-ImapMailKit -Config $Config -Password $Password -RepoRoot $RepoRoot
    $out = New-Object System.Collections.Generic.List[object]
    $orderQuery = $null
    $wantOrders = $OrdersOnly -or [bool]$Config.orders.enabled
    if ($wantOrders) { $orderQuery = Get-ImapOrderSearchQuery }
    try {
        foreach ($name in $names) {
            $count = -1
            $orderCount = -1
            $err = ''
            try {
                $folder = $client.GetFolder($name)
                [void]$folder.Open([MailKit.FolderAccess]::ReadOnly)
                $count = [int]$folder.Count
                if ($orderQuery) {
                    try { $orderCount = @($folder.Search($orderQuery)).Count }
                    catch { $orderCount = -1 }
                }
                if ($OrdersOnly -and $orderCount -ge 0) { $count = $orderCount }
            }
            catch {
                $count = -1
                $err = [string]$_.Exception.Message
            }
            $out.Add([PSCustomObject]@{ name = [string]$name; count = $count; orderCount = $orderCount; error = $err })
        }
    }
    finally {
        if ($client.IsConnected) { $client.Disconnect($true) }
        $client.Dispose()
    }
    , $out.ToArray()
}

function Get-ImapFolderMessages {
    param(
        $Config,
        [string]$Password,
        [string]$FolderName,
        [string]$RepoRoot,
        [int]$MaxMessages = 0,
        [switch]$ShowProgress,
        [switch]$OrdersOnly,
        [int]$FolderIndex = 0,
        [int]$FolderCount = 0,
        [int]$OverallBase = 0,
        [int]$OverallTotal = 0
    )
    $self = Get-NormalizedEmailList $Config.self.emails
    $user = ([string]$Config.imap.user).ToLowerInvariant()
    if ($MaxMessages -le 0 -and $Config.imap.PSObject.Properties.Name -contains 'maxMessagesPerFolder') {
        $MaxMessages = [int]$Config.imap.maxMessagesPerFolder
    }
    $client = Connect-ImapMailKit -Config $Config -Password $Password -RepoRoot $RepoRoot
    try {
        $folder = $client.GetFolder($FolderName)
        [void]$folder.Open([MailKit.FolderAccess]::ReadOnly)
        if ($OrdersOnly) {
            $uids = @($folder.Search((Get-ImapOrderSearchQuery)))
            if ($ShowProgress) {
                Write-Host '  Szukam potwierdzeń zamówień w [' -ForegroundColor White -NoNewline
                Write-Host $FolderName -ForegroundColor Cyan -NoNewline
                Write-Host '] → ' -ForegroundColor White -NoNewline
                Write-Host $uids.Count -ForegroundColor Cyan -NoNewline
                Write-Host ' trafień' -ForegroundColor White
            }
        }
        else {
            $uids = @($folder.Search([MailKit.Search.SearchQuery]::All))
            if ($MaxMessages -gt 0 -and $uids.Count -gt $MaxMessages) {
                # najnowsze N (UID rosną z czasem). Limit jest twardy: nie dociągamy starszych potwierdzeń.
                $uids = @($uids[($uids.Count - $MaxMessages)..($uids.Count - 1)])
            }
        }
        if ($OrdersOnly -and $MaxMessages -gt 0 -and $uids.Count -gt $MaxMessages) {
            $uids = @($uids[($uids.Count - $MaxMessages)..($uids.Count - 1)])
        }
        $total = $uids.Count
        $out = New-Object System.Collections.Generic.List[object]
        $i = 0
        foreach ($uid in $uids) {
            $i++
            $msg = $folder.GetMessage($uid)
            $row = ConvertFrom-MimeMessage $msg $FolderName
            $row.uid = [string]$uid
            # Potwierdzenia Shoper przychodzą OD sklepu (From = self) — zostawiamy je.
            # Resztę maili od siebie pomijamy (to nie są stopy klientów).
            $fromSelf = ($row.fromEmail -eq $user -or $self -contains $row.fromEmail)
            $isOrderMail = Test-ShoperOrderSubject $row.subject
            if ($fromSelf -and -not $OrdersOnly -and -not $isOrderMail) {
                if ($ShowProgress) {
                    Write-ImapFetchProgress -FolderName $FolderName -Done $i -Total $total `
                        -FolderIndex $FolderIndex -FolderCount $FolderCount `
                        -OverallDone ($OverallBase + $i) -OverallTotal $OverallTotal
                }
                continue
            }
            $out.Add($row)
            if ($ShowProgress) {
                Write-ImapFetchProgress -FolderName $FolderName -Done $i -Total $total `
                    -FolderIndex $FolderIndex -FolderCount $FolderCount `
                    -OverallDone ($OverallBase + $i) -OverallTotal $OverallTotal
            }
        }
        if ($ShowProgress) {
            Write-ImapFetchProgress -FolderName $FolderName -Done $total -Total $total `
                -FolderIndex $FolderIndex -FolderCount $FolderCount `
                -OverallDone ($OverallBase + $total) -OverallTotal $OverallTotal -Finish
            Write-Host '  → pobrano ' -ForegroundColor White -NoNewline
            Write-Host $out.Count -ForegroundColor Green -NoNewline
            Write-Host '  (zamykam IMAP…)' -ForegroundColor DarkGray
        }
        $result = , $out.ToArray()
        return $result
    }
    finally {
        # Logout + Dispose of ~N MimeMessage trees can take seconds with no other UI.
        try {
            if ($client -and $client.IsConnected) { $client.Disconnect($true) }
        }
        catch { }
        if ($client) { $client.Dispose() }
    }
}
