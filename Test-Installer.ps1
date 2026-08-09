# Test-Installer.ps1
# Installe et verifie Session Audio dans un dossier temporaire isole.
# By Mamat

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$InstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedInstaller = (Resolve-Path -LiteralPath $InstallerPath).Path
$testRoot = Join-Path $env:TEMP ("SessionAudioInstallerTest-" + [Guid]::NewGuid().ToString("N"))
$testInstall = Join-Path $testRoot "App"

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

try {
  $setupArguments = @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/NORESTART",
    "/NOICONS",
    ('/DIR="' + $testInstall + '"')
  )
  $setupProcess = Start-Process -FilePath $resolvedInstaller -ArgumentList $setupArguments -Wait -PassThru
  if ($setupProcess.ExitCode -ne 0) {
    throw "Installation silencieuse en echec (code $($setupProcess.ExitCode))."
  }

  $expectedFiles = @(
    "Audio-Live.ps1",
    "Audio-Live.apps.json",
    "Audio-Live.apps.example.json",
    "Mode_Audio.pow",
    "Session_Audio.ico",
    "SessionAudioLauncher.exe",
    "unins000.exe"
  )
  foreach ($fileName in $expectedFiles) {
    $expectedPath = Join-Path $testInstall $fileName
    if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
      throw "Fichier installe manquant : $expectedPath"
    }
  }

  $parseTokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $testInstall "Audio-Live.ps1"),
    [ref]$parseTokens,
    [ref]$parseErrors
  ) | Out-Null
  if (@($parseErrors).Count -gt 0) {
    throw "Le script PowerShell installe contient des erreurs de syntaxe."
  }

  $installedConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $testInstall "Audio-Live.apps.json") | ConvertFrom-Json
  if ($installedConfig.windowsSecurity.disableFirewall -or
      $installedConfig.windowsSecurity.disableDefenderRealtime -or
      $installedConfig.windowsSecurity.disableDefenderScheduledTasks) {
    throw "Une option de securite sensible est active dans la configuration installee."
  }

  $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
  $simulationOutput = & $windowsPowerShell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testInstall "Audio-Live.ps1") -NoGui -Simulate 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "La simulation de la version installee a echoue : $($simulationOutput -join ' ')"
  }
  if (($simulationOutput -join [Environment]::NewLine) -notmatch "Simulation terminee") {
    throw "La simulation installee ne confirme pas sa fin."
  }
  if (Test-Path -LiteralPath (Join-Path $testInstall "Audio-Live.state.json")) {
    throw "La simulation a cree un snapshot de restauration."
  }

  $uninstaller = Join-Path $testInstall "unins000.exe"
  $uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") -Wait -PassThru
  if ($uninstallProcess.ExitCode -ne 0) {
    throw "Desinstallation silencieuse en echec (code $($uninstallProcess.ExitCode))."
  }
  if (Test-Path -LiteralPath (Join-Path $testInstall "SessionAudioLauncher.exe")) {
    throw "Le lanceur est encore present apres desinstallation."
  }

  Write-Host "Test installeur OK : installation, simulation et desinstallation validees."
}
finally {
  $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
  $resolvedTempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
  if ($resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $resolvedTestRoot).StartsWith("SessionAudioInstallerTest-")) {
    if (Test-Path -LiteralPath $resolvedTestRoot) {
      Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
  }
}
