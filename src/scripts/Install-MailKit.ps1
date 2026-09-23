#Requires -Version 5.1
param([string]$RepoRoot = '')
$ErrorActionPreference = 'Stop'
# nuget.org wymaga TLS 1.2 (Windows PowerShell 5.1 domyślnie bywa na 1.0)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\MailToContacts.ps1'))) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'src\MailToContacts.ps1'))) {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    }
}

$ps5 = $PSVersionTable.PSVersion.Major -lt 6
$tfmOrder = if ($ps5) {
    # Prefer .NET Framework builds on Windows PowerShell 5.1 — never net8.0.
    @('lib\net48', 'lib\net472', 'lib\net47', 'lib\net462', 'lib\netstandard2.0', 'lib\net461', 'lib\net46')
}
else {
    @('lib\net8.0', 'lib\netstandard2.1', 'lib\netstandard2.0', 'lib\net48', 'lib\net462')
}

$dest = Join-Path $RepoRoot 'lib\mailkit'
if (Test-Path -LiteralPath $dest) {
    Get-ChildItem -LiteralPath $dest -File | Where-Object { $_.Extension -in '.dll', '.xml', '.pdb' } | Remove-Item -Force
}
[IO.Directory]::CreateDirectory($dest) | Out-Null

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('mailkit-' + [guid]::NewGuid().ToString('n'))
[IO.Directory]::CreateDirectory($tmp) | Out-Null

# MailKit 4.17 + transitive deps needed on .NET Framework / Windows PowerShell 5.1
$packages = @(
    @{ Name = 'System.ValueTuple'; Version = '4.5.0' }
    @{ Name = 'System.Numerics.Vectors'; Version = '4.5.0' }
    @{ Name = 'System.Buffers'; Version = '4.6.1' }
    @{ Name = 'System.Runtime.CompilerServices.Unsafe'; Version = '6.1.2' }
    @{ Name = 'System.Memory'; Version = '4.6.3' }
    @{ Name = 'System.Threading.Tasks.Extensions'; Version = '4.6.3' }
    @{ Name = 'System.Text.Encoding.CodePages'; Version = '8.0.0' }
    @{ Name = 'System.Formats.Asn1'; Version = '8.0.1' }
    @{ Name = 'System.Security.Cryptography.Pkcs'; Version = '8.0.1' }
    @{ Name = 'System.Data.DataSetExtensions'; Version = '4.5.0' }
    @{ Name = 'BouncyCastle.Cryptography'; Version = '2.6.2' }
    @{ Name = 'MimeKit'; Version = '4.17.0' }
    @{ Name = 'MailKit'; Version = '4.17.0' }
)

function Get-BestLibDir {
    param([string]$ExtractRoot, [string[]]$Order)
    foreach ($tfm in $Order) {
        $candidate = Join-Path $ExtractRoot $tfm
        if (Test-Path -LiteralPath $candidate) {
            $dlls = @(Get-ChildItem -LiteralPath $candidate -Filter '*.dll' -ErrorAction SilentlyContinue)
            if ($dlls.Count -gt 0) { return $candidate }
        }
    }
    $any = Get-ChildItem -LiteralPath $ExtractRoot -Recurse -Filter '*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match '\\lib\\' } |
        Select-Object -First 1
    if ($any) { return $any.DirectoryName }
    return $null
}

try {
    Write-Host ("PowerShell {0} — TFM: {1}" -f $PSVersionTable.PSVersion, ($tfmOrder -join ', '))
    foreach ($p in $packages) {
        $nupkg = Join-Path $tmp "$($p.Name).nupkg"
        $url = "https://www.nuget.org/api/v2/package/$($p.Name)/$($p.Version)"
        Write-Host "Pobieram $($p.Name) $($p.Version)…"
        Invoke-WebRequest -Uri $url -OutFile $nupkg -UseBasicParsing
        $extract = Join-Path $tmp $p.Name
        $zip = Join-Path $tmp "$($p.Name).zip"
        Copy-Item -LiteralPath $nupkg -Destination $zip -Force
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $lib = Get-BestLibDir -ExtractRoot $extract -Order $tfmOrder
        if (-not $lib) {
            Write-Warning "Brak DLL dla $($p.Name) ($($tfmOrder[0])) — pomijam."
            continue
        }
        Copy-Item -Path (Join-Path $lib '*.dll') -Destination $dest -Force
        Write-Host "  $($p.Name) ← $lib"
    }
    $note = if ($ps5) { 'netfx-ps51' } else { 'net8-or-ns2' }
    [IO.File]::WriteAllText((Join-Path $dest 'tfm.txt'), $note)
    Write-Host "OK → $dest"
    Get-ChildItem $dest -Filter '*.dll' | ForEach-Object { Write-Host "  $($_.Name)" }
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
