# Build-Installer.ps1
# Compile le lanceur natif et l'installeur Windows de Session Audio.
# By Mamat

[CmdletBinding()]
param(
  [switch]$UseLocalConfiguration,
  [switch]$Test
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Join-Path $projectRoot "installer"
$buildRoot = Join-Path $installerRoot "build"
$outputRoot = Join-Path $installerRoot "output"
$distRoot = Join-Path $projectRoot "dist"
$version = (Get-Content -Raw -LiteralPath (Join-Path $projectRoot "VERSION")).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+$') {
  throw "Version invalide dans VERSION : $version"
}

foreach ($path in @($buildRoot, $outputRoot, $distRoot)) {
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force
  }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
}

$cscCandidates = @(
  (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
  (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$cscPath = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $cscPath) {
  throw "Compilateur C# .NET Framework introuvable."
}

$innoCandidates = @(
  (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
  (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
  (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
)
$isccPath = $innoCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $isccPath) {
  throw "Inno Setup 6 est requis. Installez-le avec : winget install --id JRSoftware.InnoSetup -e"
}

$launcherSourceTemplate = Join-Path $installerRoot "SessionAudioLauncher.cs"
$launcherSource = Join-Path $buildRoot "SessionAudioLauncher.cs"
$launcherManifest = Join-Path $installerRoot "SessionAudioLauncher.manifest"
$launcherOutput = Join-Path $buildRoot "SessionAudioLauncher.exe"
$iconPath = Join-Path $projectRoot "Session_Audio.ico"

$assemblyVersion = "$version.0"
$launcherSourceText = [System.IO.File]::ReadAllText($launcherSourceTemplate)
$launcherSourceText = [regex]::Replace(
  $launcherSourceText,
  'AssemblyVersion\("[^"]+"\)',
  "AssemblyVersion(`"$assemblyVersion`")"
)
$launcherSourceText = [regex]::Replace(
  $launcherSourceText,
  'AssemblyFileVersion\("[^"]+"\)',
  "AssemblyFileVersion(`"$assemblyVersion`")"
)
[System.IO.File]::WriteAllText($launcherSource, $launcherSourceText, (New-Object System.Text.UTF8Encoding($false)))

$cscArguments = @(
  "/nologo",
  "/target:winexe",
  "/platform:anycpu",
  "/optimize+",
  "/reference:System.Windows.Forms.dll",
  "/win32icon:$iconPath",
  "/win32manifest:$launcherManifest",
  "/out:$launcherOutput",
  $launcherSource
)

& $cscPath @cscArguments
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $launcherOutput)) {
  throw "La compilation du lanceur natif a echoue."
}

$configurationSource = Join-Path $projectRoot "Audio-Live.apps.example.json"
$exportArguments = @{
  SourcePath = $configurationSource
  DestinationPath = (Join-Path $buildRoot "Audio-Live.apps.bootstrap.json")
}

if ($UseLocalConfiguration) {
  $localConfiguration = Join-Path $projectRoot "Audio-Live.apps.json"
  if (-not (Test-Path -LiteralPath $localConfiguration)) {
    throw "Configuration locale introuvable : $localConfiguration"
  }
  $exportArguments.SourcePath = $localConfiguration
  $exportArguments.KeepProfiles = $true
}

& (Join-Path $projectRoot "tools\Export-SafeConfiguration.ps1") @exportArguments

$innoScript = Join-Path $installerRoot "SessionAudio.iss"
& $isccPath "/DAppVersion=$version" $innoScript
if ($LASTEXITCODE -ne 0) {
  throw "La compilation de l'installeur a echoue."
}

$installerName = "Session-Audio-Setup-$version.exe"
$compiledInstaller = Join-Path $outputRoot $installerName
$publishedInstaller = Join-Path $distRoot $installerName
if (-not (Test-Path -LiteralPath $compiledInstaller)) {
  throw "Installeur compile introuvable : $compiledInstaller"
}

Copy-Item -LiteralPath $compiledInstaller -Destination $publishedInstaller -Force
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $publishedInstaller).Hash.ToLowerInvariant()
$hashPath = Join-Path $distRoot "Session-Audio-Setup-$version.sha256.txt"
[System.IO.File]::WriteAllText(
  $hashPath,
  "$hash  $installerName" + [Environment]::NewLine,
  (New-Object System.Text.UTF8Encoding($false))
)

if ($Test) {
  & (Join-Path $projectRoot "Test-Installer.ps1") -InstallerPath $publishedInstaller
}

Write-Host ""
Write-Host "Installeur cree : $publishedInstaller"
Write-Host "SHA-256          : $hash"
