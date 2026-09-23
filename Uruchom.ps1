#Requires -Version 5.1
<#
.SYNOPSIS
  Jedna komenda Shoper/Shoparena: e-mail → config → stopy/Ollama → foldery → run → VCF.
  Warstwy: potwierdzenia zamówień → stopy korespondencji → opcjonalnie lokalna Ollama.
#>
[CmdletBinding()]
param(
    [string]$Email = ''
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$cli = Join-Path $PSScriptRoot 'src\MailToContacts.ps1'
if (-not (Test-Path -LiteralPath $cli)) { throw "Nie znaleziono $cli — uruchom z katalogu repo (obok README.md)." }
& $cli setup -Email $Email
