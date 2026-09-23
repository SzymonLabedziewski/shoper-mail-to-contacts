# Local Ollama only. Structured JSON + grounding. Never send mailbox content to a cloud LLM from this module.

function Get-ExtractedFieldsSchema {
    return @{
        type       = 'object'
        properties = @{
            firstname  = @{ type = 'string' }
            surname    = @{ type = 'string' }
            role       = @{ type = 'string' }
            company    = @{ type = 'string' }
            street     = @{ type = 'string' }
            zip        = @{ type = 'string' }
            city       = @{ type = 'string' }
            phones     = @{ type = 'array'; items = @{ type = 'string' } }
            emails     = @{ type = 'array'; items = @{ type = 'string' } }
            www        = @{ type = 'string' }
            nip        = @{ type = 'string' }
            regon      = @{ type = 'string' }
            krs        = @{ type = 'string' }
            iban       = @{ type = 'string' }
            confidence = @{ type = 'number' }
        }
        required   = @()
    }
}

function Test-OllamaAvailable {
    <# Ping lokalnego daemona. Sama instalacja nie wystarcza — program Ollama musi dzialac. #>
    param(
        [string]$Url = 'http://127.0.0.1:11434',
        [int]$TimeoutSec = 3
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        $uri = $Url.TrimEnd('/') + '/api/tags'
        Invoke-RestMethod -Method Get -Uri $uri -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-OllamaExecutable {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source)) { return [string]$cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        'C:\Program Files\Ollama\ollama.exe'
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Get-OllamaAppExecutable {
    param([string]$CliExe = '')
    $candidates = @()
    if ($CliExe) {
        $candidates += (Join-Path (Split-Path -Parent $CliExe) 'ollama app.exe')
    }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe')
    $candidates += 'C:\Program Files\Ollama\ollama app.exe'
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Start-OllamaDaemon {
    <#
      Jesli Ollama jest zainstalowana, ale nie slucha na porcie — uruchom aplikacje (zasobnik)
      albo `ollama serve`. Czeka krotko na /api/tags.
    #>
    param(
        [string]$Executable = '',
        [string]$Url = 'http://127.0.0.1:11434',
        [int]$WaitSec = 20
    )
    if ([string]::IsNullOrWhiteSpace($Executable)) { $Executable = Get-OllamaExecutable }
    if (-not $Executable) { return $false }
    $app = Get-OllamaAppExecutable -CliExe $Executable
    try {
        if ($app) {
            Start-Process -FilePath $app -WindowStyle Hidden | Out-Null
        }
        else {
            Start-Process -FilePath $Executable -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
        }
    }
    catch {
        return $false
    }
    $deadline = (Get-Date).AddSeconds($WaitSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaAvailable -Url $Url -TimeoutSec 2) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-OllamaAvailable -Url $Url -TimeoutSec 2)
}

function Test-OllamaModelPresent {
    param(
        [string]$Url = 'http://127.0.0.1:11434',
        [string]$Model = 'qwen2.5:3b-instruct-q4_K_M'
    )
    try {
        $resp = Invoke-RestMethod -Method Get -Uri ($Url.TrimEnd('/') + '/api/tags') -TimeoutSec 5 -ErrorAction Stop
    }
    catch { return $false }
    $want = ([string]$Model).ToLowerInvariant()
    foreach ($m in @($resp.models)) {
        $name = ([string]$m.name).ToLowerInvariant()
        if ($name -eq $want -or $name.StartsWith($want + ':')) { return $true }
    }
    return $false
}

function Install-OllamaWithWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $false }
    Write-Host 'Instaluję Ollamę (winget, Ollama.Ollama)...' -ForegroundColor White
    & winget install --id Ollama.Ollama -e --accept-package-agreements --accept-source-agreements
    return ($LASTEXITCODE -eq 0 -or (Get-OllamaExecutable))
}

function Invoke-OllamaPull {
    param(
        [string]$Executable,
        [string]$Model
    )
    if (-not $Executable) { $Executable = Get-OllamaExecutable }
    if (-not $Executable) { return $false }
    Write-Host ("Pobieram model {0} (ok. 2 GB, może potrwać)..." -f $Model) -ForegroundColor White
    & $Executable pull $Model
    return ($LASTEXITCODE -eq 0)
}

function Ensure-OllamaReady {
    <#
      Wolane z kreatora, gdy uzytkownik chce Ollame.
      Zwraca $true tylko gdy daemon dziala i model jest na dysku.
    #>
    param($Config)
    $url = [string]$Config.ollama.url
    if (-not $url) { $url = 'http://127.0.0.1:11434' }
    $model = [string]$Config.ollama.model
    if (-not $model) { $model = 'qwen2.5:3b-instruct-q4_K_M' }

    $up = Test-OllamaAvailable -Url $url
    if (-not $up) {
        $exe = Get-OllamaExecutable
        if ($exe) {
            Write-Ui Warn 'Ollama jest zainstalowana, ale nie jest uruchomiona.'
            Write-Ui Info 'Samo pobranie nie wystarcza: trzeba włączyć program Ollama (ikona przy zegarze) albo pozwolić skryptowi go wystartować.'
            if (Read-HostYesNo 'Uruchomić Ollamę teraz?' $true) {
                Write-Ui Info 'Startuję Ollamę...'
                $up = Start-OllamaDaemon -Executable $exe -Url $url
                if (-not $up) {
                    Write-Ui Err 'Nie udało się. Otwórz Ollamę z menu Start i uruchom kreator jeszcze raz.'
                }
            }
        }
        else {
            Write-Ui Warn 'Ollama nie jest zainstalowana.'
            Write-Ui Info 'Bez niej książka i tak powstanie (reguły na stopkach). Ollama tylko dopowiada słabe stopki i zostaje na tym PC.'
            if (Read-HostYesNo 'Zainstalować Ollamę przez winget i pobrać model?' $false) {
                if (-not (Install-OllamaWithWinget)) {
                    Write-Ui Err 'Instalacja winget nie powiodła się.'
                    Write-Ui Info 'Pobierz instalator: https://ollama.com/download/windows'
                    Write-Ui Info 'Po instalacji włącz Ollamę z menu Start, potem ponownie .\Uruchom.ps1'
                    return $false
                }
                $exe = Get-OllamaExecutable
                Write-Ui Info 'Startuję Ollamę...'
                $up = Start-OllamaDaemon -Executable $exe -Url $url -WaitSec 40
                if (-not $up) {
                    Write-Ui Err 'Ollama zainstalowana, ale jeszcze nie odpowiada. Włącz ją z menu Start i uruchom kreator ponownie.'
                    return $false
                }
            }
        }
    }

    if (-not $up) { return $false }

    Write-Ui Ok ("Ollama działa ({0})." -f $url)
    if (Test-OllamaModelPresent -Url $url -Model $model) {
        Write-Ui Ok ("Model jest na dysku: {0}" -f $model)
        return $true
    }
    Write-Ui Warn ("Brak modelu {0}." -f $model)
    Write-Ui Info 'Pobranie to ok. 2 GB. Bez modelu słabe stopki zostaną w ai_queue.jsonl.'
    if (-not (Read-HostYesNo 'Pobrać model teraz (ollama pull)?' $true)) { return $false }
    $exe = Get-OllamaExecutable
    if (-not (Invoke-OllamaPull -Executable $exe -Model $model)) {
        Write-Ui Err 'Nie udało się pobrać modelu.'
        return $false
    }
    if (Test-OllamaModelPresent -Url $url -Model $model) {
        Write-Ui Ok ("Model gotowy: {0}" -f $model)
        return $true
    }
    Write-Ui Warn 'Polecenie pull skończyło się, ale modelu nie widać na liście.'
    return $false
}

function Invoke-OllamaExtract {
    param(
        $Hit,
        [string]$Url = 'http://127.0.0.1:11434',
        [string]$Model = 'qwen2.5:3b-instruct-q4_K_M'
    )
    $payload = @{
        model    = $Model
        stream   = $false
        format   = Get-ExtractedFieldsSchema
        options  = @{ temperature = 0 }
        messages = @(
            @{
                role    = 'system'
                content = 'Extract contact fields from this email signature. Polish language. Use empty string when unknown. Never invent NIP, phone, or email that is not in the text.'
            }
            @{ role = 'user'; content = $Hit.block }
        )
    }
    $body = $payload | ConvertTo-Json -Depth 8 -Compress
    try {
        $resp = Invoke-RestMethod -Method Post -Uri ($Url.TrimEnd('/') + '/api/chat') `
            -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 120 -ErrorAction Stop
    }
    catch {
        # Nie przerywaj całego run — hit zostaje w kolejce bez modelu.
        Write-Warning ("Ollama: pomijam stopkę ({0})" -f $_.Exception.Message)
        return $Hit
    }
    $content = $resp.message.content
    if (-not $content) { $content = '{}' }
    try {
        $parsed = $content | ConvertFrom-Json
    }
    catch {
        Write-Warning 'Ollama: odpowiedź nie jest JSON — zostawiam reguły.'
        return $Hit
    }
    $ext = New-ExtractedFields
    foreach ($p in $ext.PSObject.Properties.Name) {
        if ($parsed.PSObject.Properties.Name -contains $p) { $ext.$p = $parsed.$p }
    }
    $guard = Remove-HallucinatedFields $ext $Hit.block
    $ext = $guard.Extracted
    $base = $Hit.extracted
    foreach ($field in @('firstname', 'surname', 'company', 'nip', 'street', 'zip', 'city')) {
        if (-not $ext.$field -and $base.$field) { $ext.$field = $base.$field }
    }
    if (-not @($ext.emails).Count) { $ext.emails = @($base.emails) }
    if (-not @($ext.phones).Count) { $ext.phones = @($base.phones) }
    $joinedName = ("{0} {1}" -f $ext.firstname, $ext.surname).Trim()
    $again = Split-PersonName $joinedName
    if (-not $again.Firstname -or -not $again.Surname) {
        $ext.firstname = ""
        $ext.surname = ""
    }
    else {
        $ext.firstname = $again.Firstname
        $ext.surname = $again.Surname
    }
    if (Test-RosterBlock $Hit.block) {
        $ext.firstname = ""
        $ext.surname = ""
    }
    if ($ext.company -and -not (Test-LooksLikeCompanyLine $ext.company)) { $ext.company = "" }
    $Hit.extracted = $ext
    $Hit.droppedFields = @($guard.Dropped)
    $Hit.model = $Model
    return $Hit
}
