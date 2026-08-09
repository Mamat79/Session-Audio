# Export-SafeConfiguration.ps1
# Genere une configuration distribuable sans reprendre les choix sensibles du poste.
# By Mamat

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$SourcePath,
  [Parameter(Mandatory=$true)][string]$DestinationPath,
  [switch]$KeepProfiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Set-JsonProperty {
  param(
    [Parameter(Mandatory=$true)][object]$InputObject,
    [Parameter(Mandatory=$true)][string]$Name,
    [object]$Value
  )

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) {
    $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $property.Value = $Value
  }
}

function Convert-ToPortablePath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

  $result = $Path
  $replacements = @(
    [pscustomobject]@{ Value = $env:LOCALAPPDATA; Token = "%LOCALAPPDATA%" },
    [pscustomobject]@{ Value = $env:APPDATA; Token = "%APPDATA%" },
    [pscustomobject]@{ Value = $env:USERPROFILE; Token = "%USERPROFILE%" }
  )

  foreach ($replacement in $replacements) {
    if (-not [string]::IsNullOrWhiteSpace([string]$replacement.Value) -and
        $result.StartsWith([string]$replacement.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
      return [string]$replacement.Token + $result.Substring(([string]$replacement.Value).Length)
    }
  }

  return $result
}

$resolvedSource = [System.IO.Path]::GetFullPath($SourcePath)
$resolvedDestination = [System.IO.Path]::GetFullPath($DestinationPath)
if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
  throw "Configuration source introuvable : $resolvedSource"
}

$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedSource | ConvertFrom-Json

Set-JsonProperty -InputObject $config -Name "logsFolder" -Value "Logs"

$security = $config.PSObject.Properties["windowsSecurity"].Value
if ($null -eq $security) {
  $security = [pscustomobject][ordered]@{}
  Set-JsonProperty -InputObject $config -Name "windowsSecurity" -Value $security
}
Set-JsonProperty -InputObject $security -Name "disableFirewall" -Value $false
Set-JsonProperty -InputObject $security -Name "disableDefenderRealtime" -Value $false
Set-JsonProperty -InputObject $security -Name "disableDefenderScheduledTasks" -Value $false
Set-JsonProperty -InputObject $security -Name "requireConfirmation" -Value $true

foreach ($entry in @($config.apps)) {
  Set-JsonProperty -InputObject $entry -Name "enabled" -Value $false
  $pathProperty = $entry.PSObject.Properties["path"]
  if ($null -ne $pathProperty) {
    $pathProperty.Value = Convert-ToPortablePath -Path ([string]$pathProperty.Value)
  }
}

foreach ($collectionName in @("services", "processes", "networkAdapters", "stopServices")) {
  $collectionProperty = $config.PSObject.Properties[$collectionName]
  if ($null -eq $collectionProperty) { continue }

  foreach ($entry in @($collectionProperty.Value)) {
    Set-JsonProperty -InputObject $entry -Name "enabled" -Value $false
    if ($collectionName -eq "networkAdapters") {
      Set-JsonProperty -InputObject $entry -Name "audioKeep" -Value $false
    }
  }
}

if (-not $KeepProfiles) {
  $plan = $config.PSObject.Properties["audioPlan"].Value
  $defaultProfile = [pscustomobject][ordered]@{
    name = "Defaut"
    audioPlanName = if ($plan) { [string]$plan.name } else { "Mode Audio" }
    audioPlanGuid = if ($plan) { [string]$plan.expectedGuid } else { "" }
    apps = @()
    services = @()
    processes = @()
    networkAdapters = @()
  }
  Set-JsonProperty -InputObject $config -Name "activeProfile" -Value "Defaut"
  Set-JsonProperty -InputObject $config -Name "profiles" -Value @($defaultProfile)
}

$destinationDirectory = Split-Path -Parent $resolvedDestination
if (-not (Test-Path -LiteralPath $destinationDirectory)) {
  New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
}

$json = $config | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText(
  $resolvedDestination,
  $json + [Environment]::NewLine,
  (New-Object System.Text.UTF8Encoding($false))
)

Write-Host "Configuration sure exportee : $resolvedDestination"
