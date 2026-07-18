# Audio-Live.ps1
# Lance une session audio Windows : configuration PC, choix des logiciels,
# journalisation et restauration simple de l'environnement precedent.
# Script prepare pour Mamat.
# By Mamat
#
# Fichiers attendus dans ce dossier :
# - Audio-Live.apps.json : memorise les logiciels, services et le plan choisi.
# - Mode_Audio.pow : sert a recreer le plan "Mode Audio" s'il manque dans Windows.
# - Session_Audio.ico : icone optionnelle de la fenetre.
#
# Le lanceur .bat demande les droits administrateur, puis appelle ce script.

[CmdletBinding()]
param(
  [switch]$NoGui,
  [switch]$Simulate,
  [switch]$Restore,
  [switch]$OpenConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} catch {}

if (-not ("SessionAudioListViewItemComparer" -as [type])) {
  Add-Type -ReferencedAssemblies "System.Windows.Forms" -TypeDefinition @"
using System;
using System.Collections;
using System.Windows.Forms;

public class SessionAudioListViewItemComparer : IComparer
{
  private int column;
  private bool ascending;

  public SessionAudioListViewItemComparer(int column, bool ascending)
  {
    this.column = column;
    this.ascending = ascending;
  }

  public int Compare(object x, object y)
  {
    string a = ((ListViewItem)x).SubItems[column].Text;
    string b = ((ListViewItem)y).SubItems[column].Text;
    int result = String.Compare(a, b, StringComparison.CurrentCultureIgnoreCase);
    return ascending ? result : -result;
  }
}
"@
}

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$PowerCfg = Join-Path $env:SystemRoot "System32\powercfg.exe"
$ScExe = Join-Path $env:SystemRoot "System32\sc.exe"
$ConfigPath = Join-Path $ScriptRoot "Audio-Live.apps.json"
$StatePath = Join-Path $ScriptRoot "Audio-Live.state.json"
$IconPath = Join-Path $ScriptRoot "Session_Audio.ico"
$script:LogFile = $null

# Petits utilitaires pour lire/ecrire la configuration sans casser les anciens fichiers JSON.
function New-Utf8NoBomEncoding {
  return [System.Text.UTF8Encoding]::new($false)
}

function Get-Prop {
  param(
    [object]$InputObject,
    [Parameter(Mandatory=$true)][string]$Name,
    [object]$Default = $null
  )

  if ($null -eq $InputObject) { return $Default }

  if ($InputObject -is [System.Collections.IDictionary]) {
    if ($InputObject.Contains($Name)) {
      $value = $InputObject[$Name]
      if ($null -eq $value) { return $Default }
      return $value
    }
    return $Default
  }

  $prop = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  if ($null -eq $prop.Value) { return $Default }

  return $prop.Value
}

function Set-Prop {
  param(
    [Parameter(Mandatory=$true)][object]$InputObject,
    [Parameter(Mandatory=$true)][string]$Name,
  [object]$Value
  )

  if ($InputObject -is [System.Collections.IDictionary]) {
    $InputObject[$Name] = $Value
    return
  }

  $prop = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $prop) {
    $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $prop.Value = $Value
  }
}

function ConvertTo-Array {
  param([object]$Value)

  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Array]) { return @($Value) }
  return @($Value)
}

function Test-EntryEnabled {
  param(
    [object]$Entry,
    [bool]$Default = $false
  )

  $value = Get-Prop -InputObject $Entry -Name "enabled" -Default $Default
  if ($value -is [bool]) { return $value }
  if ($value -is [string]) {
    return ($value.Trim().ToLowerInvariant() -in @("1", "true", "yes", "oui", "on"))
  }

  try { return [System.Convert]::ToBoolean($value) } catch { return $Default }
}

function Resolve-SessionPath {
  param([Parameter(Mandatory=$true)][string]$Path)

  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
  if ([System.IO.Path]::IsPathRooted($expanded)) {
    return [System.IO.Path]::GetFullPath($expanded)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot $expanded))
}

# Configuration par defaut utilisee au premier lancement ou si un champ manque.
function New-DefaultConfig {
  return [pscustomobject][ordered]@{
    audioPlan = [ordered]@{
      name = "Mode Audio"
      expectedGuid = "0155f4f8-4a69-4c09-9c16-62ee882a2e95"
      powFile = "Mode_Audio.pow"
    }
    logsFolder = "..\Logs"
    windowsSecurity = [ordered]@{
      disableFirewall = $false
      disableDefenderRealtime = $false
      disableDefenderScheduledTasks = $false
      requireConfirmation = $true
    }
    activeProfile = "Defaut"
    profiles = @(
      [ordered]@{
        name = "Defaut"
        audioPlanName = "Mode Audio"
        audioPlanGuid = "0155f4f8-4a69-4c09-9c16-62ee882a2e95"
        apps = @()
        services = @("Tailscale")
        processes = @()
        networkAdapters = @()
      }
    )
    stopServices = @(
      [ordered]@{
        name = "Tailscale"
        displayName = "Tailscale"
        enabled = $true
      }
    )
    services = @(
      [ordered]@{ name = "Tailscale"; displayName = "Tailscale"; action = "Stop"; enabled = $true },
      [ordered]@{ name = "nordvpn-service"; displayName = "NordVPN"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "NordUpdaterService"; displayName = "NordVPN Updater"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "Synology Drive VSS Service x64"; displayName = "Synology Drive VSS"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "DbxSvc"; displayName = "Dropbox Service"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "WSearch"; displayName = "Windows Search"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "SysMain"; displayName = "SysMain"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "DiagTrack"; displayName = "Telemetrie Windows"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "DoSvc"; displayName = "Optimisation de livraison"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "UsoSvc"; displayName = "Orchestrateur Windows Update"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "wuauserv"; displayName = "Windows Update"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "PhoneSvc"; displayName = "Service telephonique"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "ss_conn_service"; displayName = "Samsung Mobile Connectivity"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "ss_conn_service2"; displayName = "Samsung Mobile Connectivity V2"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "Spooler"; displayName = "Spouleur impression"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "DellTechHub"; displayName = "Dell TechHub"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "SupportAssistAgent"; displayName = "Dell SupportAssist"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "OptionsPlusUpdaterService"; displayName = "Logi Options Updater"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "vmcompute"; displayName = "Hyper-V Host Compute"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "WSLService"; displayName = "WSL Service"; action = "Stop"; enabled = $false },
      [ordered]@{ name = "hns"; displayName = "Host Network Service"; action = "Stop"; enabled = $false }
    )
    processes = @(
      [ordered]@{ name = "OneDrive"; displayName = "OneDrive"; action = "Close"; enabled = $false },
      [ordered]@{ name = "cloud-drive-daemon"; displayName = "Synology Drive"; action = "Close"; enabled = $false },
      [ordered]@{ name = "cloud-drive-ui"; displayName = "Synology Drive UI"; action = "Close"; enabled = $false },
      [ordered]@{ name = "PhoneExperienceHost"; displayName = "Mobile connecte Windows"; action = "Close"; enabled = $false },
      [ordered]@{ name = "CrossDeviceService"; displayName = "Lien avec telephone Windows"; action = "Close"; enabled = $false },
      [ordered]@{ name = "CrossDeviceResume"; displayName = "Reprise lien telephone Windows"; action = "Close"; enabled = $false },
      [ordered]@{ name = "logioptionsplus_agent"; displayName = "Logi Options Agent"; action = "Close"; enabled = $false },
      [ordered]@{ name = "ChatGPT"; displayName = "ChatGPT"; action = "Close"; enabled = $false },
      [ordered]@{ name = "Codex"; displayName = "Codex"; action = "Close"; enabled = $false }
    )
    networkAdapters = @(
      [ordered]@{ name = "Tailscale"; displayName = "Tailscale"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = "NordLynx"; displayName = "NordLynx"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = ("Connexion au r" + [char]0x00E9 + "seau local"); displayName = "OpenVPN TAP"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = ("Connexion au r" + [char]0x00E9 + "seau local 2"); displayName = "NordVPN TAP"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = "OpenVPN Connect DCO Adapter"; displayName = "OpenVPN DCO"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = "OpenVPN Data Channel Offload for NordVPN"; displayName = "NordVPN DCO"; action = "Disable"; enabled = $false; audioKeep = $false },
      [ordered]@{ name = ("Connexion r" + [char]0x00E9 + "seau Bluetooth 2"); displayName = "Bluetooth Network"; action = "Disable"; enabled = $false; audioKeep = $false }
    )
    apps = @(
      [ordered]@{
        name = "TASCAM UH-7000 Mixer"
        category = "Interfaces audio"
        path = "C:\Windows\usb-audio.deTascamUH7000\CPL_UH7000.EXE"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Total Mix 1"
        category = "Interfaces audio"
        path = "C:\Program Files\RME\MADIface\TotalMixFX.exe"
        delaySeconds = 2
        enabled = $false
      },
      [ordered]@{
        name = "Total Mix 2"
        category = "Interfaces audio"
        path = "C:\Program Files\RME\Fireface\TotalMixFX_x64.exe"
        delaySeconds = 2
        enabled = $false
      },
      [ordered]@{
        name = "Voicemeeter Banana"
        category = "Interfaces audio"
        path = "C:\Program Files (x86)\VB\Voicemeeter\voicemeeterpro_x64.exe"
        delaySeconds = 6
        enabled = $false
      },
      [ordered]@{
        name = "Dante Controller"
        category = "Reseau audio"
        path = "C:\Program Files\Audinate\Dante Controller\DanteController.exe"
        delaySeconds = 4
        enabled = $true
      },
      [ordered]@{
        name = "AgoraController"
        category = "Reseau audio"
        path = "C:\Program Files\AgoraController\AgoraController.exe"
        delaySeconds = 4
        enabled = $false
      },
      [ordered]@{
        name = "Milan Manager"
        category = "Reseau audio"
        path = "C:\Program Files\Milan Manager\MilanManager.exe"
        delaySeconds = 6
        enabled = $false
      },
      [ordered]@{
        name = "Net Set Man"
        category = "Reseau audio"
        path = "C:\Program Files (x86)\NetSetMan\netsetman.exe"
        delaySeconds = 1
        enabled = $true
      },
      [ordered]@{
        name = "Rustdesk"
        category = "Reseau audio"
        path = "C:\Program Files\RustDesk\rustdesk.exe"
        delaySeconds = 1
        enabled = $false
      },
      [ordered]@{
        name = "dLive Director"
        category = "Consoles"
        path = "C:\Program Files\Allen & Heath\dLive Director 2.12\dLive Director.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Avantis Director"
        category = "Consoles"
        path = "C:\Program Files\Allen & Heath\Avantis Director 1.34\Avantis Director.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Ql Editor"
        category = "Consoles"
        path = "C:\Program Files (x86)\Yamaha\QL Editor\ql_editor.exe"
        delaySeconds = 0
        enabled = $true
      },
      [ordered]@{
        name = "Cl Editor"
        category = "Consoles"
        path = "C:\Program Files (x86)\Yamaha\CL Editor\cl_editor.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Lake Controller"
        category = "Processeurs"
        path = "C:\Program Files (x86)\Lake\Lake Controller v8.1.7\Lake Controller.exe"
        delaySeconds = 0
        enabled = $true
      },
      [ordered]@{
        name = "Powersoft"
        category = "Processeurs"
        path = "C:\Program Files\Powersoft\ArmoniaPlus\ArmoniaPlus.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "L-Manager"
        category = "Processeurs"
        path = "C:\Program Files (x86)\L-Acoustics\LA Network Manager 2026.1\bin\LA Network Manager 2026.1.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "L-ISA Control"
        category = "Processeurs"
        path = "C:\Program Files\L-Acoustics\L-ISA Controller\L-ISA Controller.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Fohhn"
        category = "Processeurs"
        path = "C:\Program Files\Fohhn Audio AG\Fohhn Audio Soft 6.6.1\FohhnAudioSoft.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "R1 V3"
        category = "Processeurs"
        path = "C:\Program Files\dbaudio\R1 V3\R1_V3.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "LiveTrax"
        category = "Enregistrement"
        path = "C:\Program Files\LiveTrax2\bin\LiveTrax.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Mixbus10"
        category = "Enregistrement"
        path = "C:\Program Files\Mixbus10\bin\Mixbus.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Smaart"
        category = "Mesure"
        path = "C:\Program Files (x86)\Smaart 8\Smaart.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Live Capture"
        category = "Enregistrement"
        path = "C:\Program Files (x86)\Live-Capture Pro\LiveCap.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Loop Midi"
        category = "MIDI et utilitaires"
        path = "C:\Program Files (x86)\Tobias Erichsen\loopMIDI\loopMIDI.exe"
        delaySeconds = 4
        enabled = $false
      },
      [ordered]@{
        name = "Midi-OX"
        category = "MIDI et utilitaires"
        path = "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\MIDI-OX.lnk"
        delaySeconds = 1
        enabled = $false
      },
      [ordered]@{
        name = "N.O.D.E"
        category = "MIDI et utilitaires"
        path = "C:\Users\mamat\AppData\Local\ProducelyNODE\current\NODE.exe"
        delaySeconds = 10
        enabled = $false
      },
      [ordered]@{
        name = "A&H Midi TCP"
        category = "MIDI et utilitaires"
        path = "C:\Program Files (x86)\Allen & Heath\Allen and Heath MIDI Control\Allen and Heath MIDI Control.exe"
        delaySeconds = 1
        enabled = $false
      },
      [ordered]@{
        name = "Nuendo14"
        category = "DAW"
        path = "C:\Program Files\Steinberg\Nuendo 14\Nuendo14.exe"
        delaySeconds = 0
        enabled = $false
      },
      [ordered]@{
        name = "Live 12"
        category = "DAW"
        path = "C:\ProgramData\Ableton\Live 12 Suite\Program\Ableton Live 12 Suite.exe"
        delaySeconds = 0
        enabled = $false
      }
    )
  }
}

function Save-Config {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [switch]$SkipBackup
  )

  if ((-not $SkipBackup) -and (Test-Path -LiteralPath $ConfigPath)) {
    $backupPath = $ConfigPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
    $backupIndex = 2
    while (Test-Path -LiteralPath $backupPath) {
      $backupPath = $ConfigPath + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss") + "-$backupIndex"
      $backupIndex++
    }
    Copy-Item -LiteralPath $ConfigPath -Destination $backupPath -Force
  }

  $json = $Config | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($ConfigPath, $json + [Environment]::NewLine, (New-Utf8NoBomEncoding))
}

function Repair-KnownEncodingIssues {
  param([string]$Text)

  if ($null -eq $Text) { return $Text }

  return $Text.
    Replace(("r" + [char]0x00C3 + [char]0x00A9 + "seau"), ("r" + [char]0x00E9 + "seau")).
    Replace(("R" + [char]0x00C3 + [char]0x00A9 + "seau"), ("R" + [char]0x00E9 + "seau")).
    Replace(([string][char]0x00C3 + [char]0x00A9), ([string][char]0x00E9)).
    Replace(([string][char]0x00C3 + [char]0x00A8), ([string][char]0x00E8)).
    Replace(([string][char]0x00C3 + [char]0x00AA), ([string][char]0x00EA)).
    Replace(([string][char]0x00C3 + [char]0x00A0), ([string][char]0x00E0)).
    Replace(([string][char]0x00C3 + [char]0x00A7), ([string][char]0x00E7)).
    Replace(([string][char]0x00C3 + [char]0x00B4), ([string][char]0x00F4)).
    Replace(([string][char]0x00C3 + [char]0x00BB), ([string][char]0x00FB))
}

function Repair-EntryTextFields {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$true)][string]$PropertyName
  )

  $changed = $false
  $fields = @("name", "displayName", "description", "category", "path")

  foreach ($entry in (ConvertTo-Array (Get-Prop -InputObject $Config -Name $PropertyName -Default @()))) {
    foreach ($field in $fields) {
      $value = Get-Prop -InputObject $entry -Name $field -Default $null
      if ($value -isnot [string]) { continue }

      $fixed = Repair-KnownEncodingIssues -Text $value
      if ($fixed -ne $value) {
        Set-Prop -InputObject $entry -Name $field -Value $fixed
        $changed = $true
      }
    }
  }

  return $changed
}

function Repair-ProfileFields {
  param([Parameter(Mandatory=$true)][object]$Config)

  $changed = $false
  foreach ($profile in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))) {
    foreach ($field in @("name", "audioPlanName", "audioPlanGuid")) {
      $value = Get-Prop -InputObject $profile -Name $field -Default $null
      if ($value -isnot [string]) { continue }
      $fixed = Repair-KnownEncodingIssues -Text $value
      if ($fixed -ne $value) {
        Set-Prop -InputObject $profile -Name $field -Value $fixed
        $changed = $true
      }
    }

    foreach ($field in @("apps", "services", "processes", "networkAdapters")) {
      $values = @(ConvertTo-Array (Get-Prop -InputObject $profile -Name $field -Default @()))
      $fixedValues = @()
      foreach ($value in $values) {
        if ($value -is [string]) {
          $fixedValues += (Repair-KnownEncodingIssues -Text $value)
        } else {
          $fixedValues += $value
        }
      }

      if (($fixedValues -join "|") -ne ($values -join "|")) {
        Set-Prop -InputObject $profile -Name $field -Value $fixedValues
        $changed = $true
      }
    }
  }

  return $changed
}

function Remove-DuplicateEntriesByName {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$true)][string]$PropertyName
  )

  $entries = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name $PropertyName -Default @()))
  $seen = @{}
  $cleanEntries = @()
  $changed = $false

  foreach ($entry in $entries) {
    $name = [string](Get-Prop -InputObject $entry -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $key = $name.ToLowerInvariant()
    if ($seen.ContainsKey($key)) {
      $changed = $true
      continue
    }

    $seen[$key] = $true
    $cleanEntries += $entry
  }

  if ($cleanEntries.Count -ne $entries.Count) { $changed = $true }
  if ($changed) {
    Set-Prop -InputObject $Config -Name $PropertyName -Value $cleanEntries
  }

  return $changed
}

function Ensure-ActiveProfileIsValid {
  param([Parameter(Mandatory=$true)][object]$Config)

  $profiles = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))
  if ($profiles.Count -eq 0) {
    $defaults = New-DefaultConfig
    Set-Prop -InputObject $Config -Name "profiles" -Value $defaults.profiles
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $defaults.activeProfile
    return $true
  }

  $activeProfile = [string](Get-Prop -InputObject $Config -Name "activeProfile" -Default "")
  foreach ($profile in $profiles) {
    if ([string](Get-Prop -InputObject $profile -Name "name" -Default "") -eq $activeProfile) {
      return $false
    }
  }

  Set-Prop -InputObject $Config -Name "activeProfile" -Value ([string](Get-Prop -InputObject $profiles[0] -Name "name" -Default ""))
  return $true
}

function Ensure-NetworkAdapterFields {
  param([Parameter(Mandatory=$true)][object]$Config)

  $changed = $false
  foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
    if ($null -eq (Get-Prop -InputObject $adapterConfig -Name "audioKeep" -Default $null)) {
      Set-Prop -InputObject $adapterConfig -Name "audioKeep" -Value $false
      $changed = $true
    }
  }

  return $changed
}

function Add-MissingEntriesByName {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$true)][string]$PropertyName,
    [Parameter(Mandatory=$true)][object[]]$DefaultEntries
  )

  $entries = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name $PropertyName -Default @()))
  $changed = $false

  foreach ($defaultEntry in $DefaultEntries) {
    $defaultName = [string](Get-Prop -InputObject $defaultEntry -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($defaultName)) { continue }

    $exists = $false
    foreach ($entry in $entries) {
      $entryName = [string](Get-Prop -InputObject $entry -Name "name" -Default "")
      if ($entryName -eq $defaultName) {
        $exists = $true
        break
      }
    }

    if (-not $exists) {
      $entries += $defaultEntry
      $changed = $true
    }
  }

  if ($changed) {
    Set-Prop -InputObject $Config -Name $PropertyName -Value $entries
  }

  return $changed
}

function Add-MissingDescriptions {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$true)][string]$PropertyName,
    [Parameter(Mandatory=$true)][string]$Kind
  )

  $changed = $false
  foreach ($entry in (ConvertTo-Array (Get-Prop -InputObject $Config -Name $PropertyName -Default @()))) {
    $name = [string](Get-Prop -InputObject $entry -Name "name" -Default "")
    $description = [string](Get-Prop -InputObject $entry -Name "description" -Default "")
    if (-not [string]::IsNullOrWhiteSpace($description)) { continue }

    $newDescription = Get-RecommendationDescription -Kind $Kind -Name $name
    if ([string]::IsNullOrWhiteSpace($newDescription)) { continue }

    Set-Prop -InputObject $entry -Name "description" -Value $newDescription
    $changed = $true
  }

  return $changed
}

# Charge la configuration et migre les anciennes versions sans intervention.
function Read-Config {
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    $defaultConfig = New-DefaultConfig
    Save-Config -Config $defaultConfig
    return $defaultConfig
  }

  $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
  $config = $raw | ConvertFrom-Json
  $defaults = New-DefaultConfig
  $configChanged = $false

  if ($null -eq (Get-Prop -InputObject $config -Name "audioPlan" -Default $null)) {
    Set-Prop -InputObject $config -Name "audioPlan" -Value $defaults.audioPlan
    $configChanged = $true
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "logsFolder" -Default $null)) {
    Set-Prop -InputObject $config -Name "logsFolder" -Value $defaults.logsFolder
    $configChanged = $true
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "windowsSecurity" -Default $null)) {
    Set-Prop -InputObject $config -Name "windowsSecurity" -Value $defaults.windowsSecurity
    $configChanged = $true
  } else {
    $securityConfig = Get-WindowsSecurityConfig -Config $config
    foreach ($securityField in @("disableFirewall", "disableDefenderRealtime", "disableDefenderScheduledTasks", "requireConfirmation")) {
      if ($null -eq (Get-Prop -InputObject $securityConfig -Name $securityField -Default $null)) {
        Set-Prop -InputObject $securityConfig -Name $securityField -Value (Get-Prop -InputObject $defaults.windowsSecurity -Name $securityField -Default $false)
        $configChanged = $true
      }
    }
    Set-Prop -InputObject $config -Name "windowsSecurity" -Value $securityConfig
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "activeProfile" -Default $null)) {
    Set-Prop -InputObject $config -Name "activeProfile" -Value $defaults.activeProfile
    $configChanged = $true
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "profiles" -Default $null)) {
    Set-Prop -InputObject $config -Name "profiles" -Value $defaults.profiles
    $configChanged = $true
  }
  if (@(ConvertTo-Array (Get-Prop -InputObject $config -Name "stopServices" -Default @())).Count -eq 0) {
    Set-Prop -InputObject $config -Name "stopServices" -Value $defaults.stopServices
    $configChanged = $true
  }
  if (@(ConvertTo-Array (Get-Prop -InputObject $config -Name "services" -Default @())).Count -eq 0) {
    $serviceDefaults = @()
    foreach ($serviceConfig in (ConvertTo-Array (Get-Prop -InputObject $config -Name "stopServices" -Default $defaults.stopServices))) {
      $serviceDefaults += [pscustomobject][ordered]@{
        name = [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default "")
        displayName = [string](Get-Prop -InputObject $serviceConfig -Name "displayName" -Default "")
        action = "Stop"
        enabled = Test-EntryEnabled -Entry $serviceConfig -Default $true
      }
    }
    Set-Prop -InputObject $config -Name "services" -Value $serviceDefaults
    $configChanged = $true
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "processes" -Default $null)) {
    Set-Prop -InputObject $config -Name "processes" -Value $defaults.processes
    $configChanged = $true
  }
  if ($null -eq (Get-Prop -InputObject $config -Name "networkAdapters" -Default $null)) {
    Set-Prop -InputObject $config -Name "networkAdapters" -Value $defaults.networkAdapters
    $configChanged = $true
  }
  if (@(ConvertTo-Array (Get-Prop -InputObject $config -Name "apps" -Default @())).Count -eq 0) {
    Set-Prop -InputObject $config -Name "apps" -Value $defaults.apps
    $configChanged = $true
  }

  if (Add-MissingEntriesByName -Config $config -PropertyName "services" -DefaultEntries @(ConvertTo-Array $defaults.services)) {
    $configChanged = $true
  }
  if (Add-MissingEntriesByName -Config $config -PropertyName "processes" -DefaultEntries @(ConvertTo-Array $defaults.processes)) {
    $configChanged = $true
  }
  if (Add-MissingEntriesByName -Config $config -PropertyName "networkAdapters" -DefaultEntries @(ConvertTo-Array $defaults.networkAdapters)) {
    $configChanged = $true
  }
  if (Add-MissingDescriptions -Config $config -PropertyName "services" -Kind "service") {
    $configChanged = $true
  }
  if (Add-MissingDescriptions -Config $config -PropertyName "processes" -Kind "process") {
    $configChanged = $true
  }
  if (Add-MissingDescriptions -Config $config -PropertyName "networkAdapters" -Kind "network") {
    $configChanged = $true
  }
  foreach ($propertyName in @("apps", "services", "processes", "networkAdapters", "profiles")) {
    if (Repair-EntryTextFields -Config $config -PropertyName $propertyName) {
      $configChanged = $true
    }
  }
  if (Repair-ProfileFields -Config $config) {
    $configChanged = $true
  }
  foreach ($propertyName in @("apps", "services", "processes", "networkAdapters")) {
    if (Remove-DuplicateEntriesByName -Config $config -PropertyName $propertyName) {
      $configChanged = $true
    }
  }
  if (Ensure-ActiveProfileIsValid -Config $config) {
    $configChanged = $true
  }
  if (Ensure-NetworkAdapterFields -Config $config) {
    $configChanged = $true
  }

  if ($configChanged) {
    Save-Config -Config $config
  }

  return $config
}

function Initialize-Logging {
  param([Parameter(Mandatory=$true)][object]$Config)

  $logFolderSetting = [string](Get-Prop -InputObject $Config -Name "logsFolder" -Default "..\Logs")
  $logFolder = Resolve-SessionPath -Path $logFolderSetting

  if (-not (Test-Path -LiteralPath $logFolder)) {
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
  }

  $script:LogFile = Join-Path $logFolder ("AudioLive_" + (Get-Date -Format "yyyy-MM-dd_HH-mm-ss") + ".log")
}

function Write-Log {
  param([Parameter(Mandatory=$true)][string]$Message)

  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "$ts : $Message"
  Write-Host $line

  if ($script:LogFile) {
    [System.IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, (New-Utf8NoBomEncoding))
  }
}

function Open-ConfigFile {
  $config = Read-Config
  Save-Config -Config $config
  Start-Process -FilePath "notepad.exe" -ArgumentList "`"$ConfigPath`"" | Out-Null
}

function Confirm-PendingRestore {
  if (-not (Test-Path -LiteralPath $StatePath)) { return $false }

  Add-Type -AssemblyName System.Windows.Forms
  $result = [System.Windows.Forms.MessageBox]::Show(
    "Une session precedente n'a pas ete restauree.`n`nRestaurer maintenant ?",
    "Session Audio - restauration en attente",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Warning
  )

  return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
}

# Les reglages d'alimentation et de services demandent une execution administrateur.
function Test-IsAdmin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch {
    return $false
  }
}

function Get-ActivePowerSchemeGuid {
  $active = & $PowerCfg -getactivescheme 2>$null
  foreach ($line in $active) {
    if ($line -match "([0-9a-fA-F\-]{36})") { return $matches[1] }
  }
  return $null
}

function Get-PlanGuidByName {
  param([Parameter(Mandatory=$true)][string]$PlanName)

  $escapedName = [regex]::Escape($PlanName)
  $out = & $PowerCfg /list 2>$null
  foreach ($line in $out) {
    if ($line -match "([0-9a-fA-F\-]{36}).*\(\s*$escapedName\s*\)") {
      return $matches[1]
    }
  }
  return $null
}

function Get-PowerPlans {
  $plans = @()
  $activeGuid = Get-ActivePowerSchemeGuid
  $out = & $PowerCfg /list 2>$null

  foreach ($line in $out) {
    if ($line -match "([0-9a-fA-F\-]{36}).*\((.+?)\)") {
      $guid = $matches[1]
      $name = $matches[2].Trim()
      $plans += [pscustomobject][ordered]@{
        name = $name
        guid = $guid
        active = ($guid -eq $activeGuid)
        label = if ($guid -eq $activeGuid) { "$name (actif)" } else { $name }
      }
    }
  }

  return $plans
}

function Get-HibernateEnabled {
  try {
    $key = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction Stop
    return [int]$key.HibernateEnabled
  } catch {
    return $null
  }
}

# Liste unique des services geres, avec compatibilite pour l'ancien champ stopServices.
function Get-ManagedServiceConfigs {
  param([Parameter(Mandatory=$true)][object]$Config)

  $services = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "services" -Default @()))
  if ($services.Count -gt 0) { return $services }

  $legacyServices = @()
  foreach ($serviceConfig in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "stopServices" -Default @()))) {
    $legacyServices += [pscustomobject][ordered]@{
      name = [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default "")
      displayName = [string](Get-Prop -InputObject $serviceConfig -Name "displayName" -Default "")
      action = "Stop"
      enabled = Test-EntryEnabled -Entry $serviceConfig -Default $true
    }
  }

  return $legacyServices
}

function Get-ManagedProcessConfigs {
  param([Parameter(Mandatory=$true)][object]$Config)
  return @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "processes" -Default @()))
}

function Get-ManagedNetworkAdapterConfigs {
  param([Parameter(Mandatory=$true)][object]$Config)
  return @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "networkAdapters" -Default @()))
}

function Get-WindowsSecurityConfig {
  param([Parameter(Mandatory=$true)][object]$Config)

  $defaults = (New-DefaultConfig).windowsSecurity
  $securityConfig = Get-Prop -InputObject $Config -Name "windowsSecurity" -Default $null
  if ($null -eq $securityConfig) { return $defaults }
  return $securityConfig
}

function Test-WindowsSecurityOptionEnabled {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $securityConfig = Get-WindowsSecurityConfig -Config $Config
  return Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $securityConfig -Name $Name -Default $false) }) -Default $false
}

function Get-FirewallProfileState {
  $profiles = @()
  try {
    foreach ($profile in @(Get-NetFirewallProfile -ErrorAction Stop | Sort-Object Name)) {
      $profiles += [ordered]@{
        name = [string]$profile.Name
        enabled = [bool]$profile.Enabled
      }
    }
  } catch {
    return [ordered]@{
      supported = $false
      error = $_.Exception.Message
      profiles = @()
    }
  }

  return [ordered]@{
    supported = $true
    error = ""
    profiles = $profiles
  }
}

function Get-DefenderRealtimeState {
  try {
    $preference = Get-MpPreference -ErrorAction Stop
    return [ordered]@{
      supported = $true
      error = ""
      disableRealtimeMonitoring = [bool]$preference.DisableRealtimeMonitoring
    }
  } catch {
    return [ordered]@{
      supported = $false
      error = $_.Exception.Message
      disableRealtimeMonitoring = $null
    }
  }
}

function Get-DefenderScheduledTaskState {
  $tasks = @()
  try {
    foreach ($task in @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\" -ErrorAction Stop | Sort-Object TaskName)) {
      $tasks += [ordered]@{
        taskName = [string]$task.TaskName
        taskPath = [string]$task.TaskPath
        state = [string]$task.State
      }
    }
  } catch {
    return [ordered]@{
      supported = $false
      error = $_.Exception.Message
      tasks = @()
    }
  }

  return [ordered]@{
    supported = $true
    error = ""
    tasks = $tasks
  }
}

function Disable-DefenderScheduledTasks {
  try {
    $tasks = @(Get-ScheduledTask -TaskPath "\Microsoft\Windows\Windows Defender\" -ErrorAction Stop | Sort-Object TaskName)
  } catch {
    Write-Log "Securite Windows : taches planifiees Defender non lues ($($_.Exception.Message))"
    return
  }

  foreach ($task in $tasks) {
    try {
      if ([string]$task.State -eq "Disabled") {
        Write-Log ("Securite Windows : tache Defender deja desactivee : {0}" -f $task.TaskName)
        continue
      }

      if ([string]$task.State -eq "Running") {
        try {
          Stop-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
          Write-Log ("Securite Windows : tache Defender arretee : {0}" -f $task.TaskName)
        } catch {
          Write-Log "Securite Windows : tache Defender $($task.TaskName) non arretee ($($_.Exception.Message))"
        }
      }

      Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop | Out-Null
      Write-Log ("Securite Windows : tache Defender desactivee : {0}" -f $task.TaskName)
    } catch {
      Write-Log "Securite Windows : tache Defender $($task.TaskName) non modifiee ($($_.Exception.Message))"
    }
  }
}

function Get-WindowsSecurityState {
  return [ordered]@{
    firewall = Get-FirewallProfileState
    defenderRealtime = Get-DefenderRealtimeState
    defenderScheduledTasks = Get-DefenderScheduledTaskState
  }
}

function Apply-WindowsSecuritySettings {
  param([Parameter(Mandatory=$true)][object]$Config)

  $disableFirewall = Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableFirewall"
  $disableDefenderRealtime = Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableDefenderRealtime"
  $disableDefenderScheduledTasks = Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableDefenderScheduledTasks"

  if (-not $disableFirewall -and -not $disableDefenderRealtime -and -not $disableDefenderScheduledTasks) {
    Write-Log "Securite Windows : aucune action demandee"
    return
  }

  if ($disableFirewall) {
    try {
      Write-Log "Securite Windows : desactivation temporaire du pare-feu Windows"
      Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False -ErrorAction Stop
    } catch {
      Write-Log "Securite Windows : pare-feu non modifie ($($_.Exception.Message))"
    }
  }

  if ($disableDefenderRealtime) {
    try {
      Write-Log "Securite Windows : desactivation temporaire du scan temps reel Microsoft Defender"
      Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
    } catch {
      Write-Log "Securite Windows : scan temps reel Defender non modifie ($($_.Exception.Message))"
    }
  }

  if ($disableDefenderScheduledTasks) {
    Write-Log "Securite Windows : desactivation temporaire des taches planifiees Microsoft Defender"
    Disable-DefenderScheduledTasks
  }
}

function Restore-WindowsSecurityState {
  param([Parameter(Mandatory=$true)][object]$State)

  $securityState = Get-Prop -InputObject $State -Name "windowsSecurity" -Default $null
  if ($null -eq $securityState) {
    Write-Log "Securite Windows : aucun etat a restaurer"
    return
  }

  $firewallState = Get-Prop -InputObject $securityState -Name "firewall" -Default $null
  if ($null -ne $firewallState -and (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $firewallState -Name "supported" -Default $false) }) -Default $false)) {
    foreach ($profile in (ConvertTo-Array (Get-Prop -InputObject $firewallState -Name "profiles" -Default @()))) {
      $name = [string](Get-Prop -InputObject $profile -Name "name" -Default "")
      $enabled = [bool](Get-Prop -InputObject $profile -Name "enabled" -Default $true)
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      try {
        Write-Log ("Securite Windows : restauration pare-feu {0} = {1}" -f $name, $enabled)
        Set-NetFirewallProfile -Profile $name -Enabled $enabled -ErrorAction Stop
      } catch {
        Write-Log "Securite Windows : pare-feu $name non restaure ($($_.Exception.Message))"
      }
    }
  }

  $defenderState = Get-Prop -InputObject $securityState -Name "defenderRealtime" -Default $null
  if ($null -ne $defenderState -and (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $defenderState -Name "supported" -Default $false) }) -Default $false)) {
    $disableRealtime = Get-Prop -InputObject $defenderState -Name "disableRealtimeMonitoring" -Default $null
    if ($null -ne $disableRealtime) {
      try {
        Write-Log ("Securite Windows : restauration scan temps reel Defender DisableRealtimeMonitoring={0}" -f $disableRealtime)
        Set-MpPreference -DisableRealtimeMonitoring ([bool]$disableRealtime) -ErrorAction Stop
      } catch {
        Write-Log "Securite Windows : scan temps reel Defender non restaure ($($_.Exception.Message))"
      }
    }
  }

  $defenderTasksState = Get-Prop -InputObject $securityState -Name "defenderScheduledTasks" -Default $null
  if ($null -ne $defenderTasksState -and (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $defenderTasksState -Name "supported" -Default $false) }) -Default $false)) {
    foreach ($taskState in (ConvertTo-Array (Get-Prop -InputObject $defenderTasksState -Name "tasks" -Default @()))) {
      $taskName = [string](Get-Prop -InputObject $taskState -Name "taskName" -Default "")
      $taskPath = [string](Get-Prop -InputObject $taskState -Name "taskPath" -Default "\Microsoft\Windows\Windows Defender\")
      $previousState = [string](Get-Prop -InputObject $taskState -Name "state" -Default "")
      if ([string]::IsNullOrWhiteSpace($taskName)) { continue }

      try {
        if ($previousState -eq "Disabled") {
          Disable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
          Write-Log ("Securite Windows : tache Defender restauree desactivee : {0}" -f $taskName)
        } else {
          Enable-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop | Out-Null
          Write-Log ("Securite Windows : tache Defender restauree active : {0}" -f $taskName)
        }
      } catch {
        Write-Log "Securite Windows : tache Defender $taskName non restauree ($($_.Exception.Message))"
      }
    }
  }
}

function Get-RecommendationDescription {
  param(
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $key = "$Kind`:$Name".ToLowerInvariant()
  switch ($key) {
    "service:tailscale" { return "VPN maillage. A arreter si tu veux eviter les tunnels reseau pendant une session audio." }
    "service:nordvpn-service" { return "Service VPN NordVPN. Peut ajouter des interfaces reseau et perturber certains flux audio reseau." }
    "service:nordupdaterservice" { return "Mise a jour NordVPN. Peu utile pendant une session critique." }
    "service:synology drive vss service x64" { return "Composant Synology Drive. Peut declencher de la synchro ou de l'activite disque." }
    "service:dbxsvc" { return "Service Dropbox. Candidat a l'arret si tu veux limiter les synchronisations cloud." }
    "service:wsearch" { return "Indexation Windows. Peut generer de l'activite disque en arriere-plan." }
    "service:sysmain" { return "Cache et prechargement Windows. A tester, parfois utile, parfois bruyant pour l'audio." }
    "service:diagtrack" { return "Telemetrie Windows. Peu utile pendant une session audio." }
    "service:dosvc" { return "Optimisation de livraison Windows Update. Peut utiliser disque et reseau." }
    "service:usosvc" { return "Orchestration Windows Update. A couper seulement pendant une session courte, puis restaurer." }
    "service:wuauserv" { return "Windows Update. A couper pendant une session critique, puis restaurer." }
    "service:phonesvc" { return "Fonctions telephonie Windows. Generalement inutile pour une session audio." }
    "service:ss_conn_service" { return "Connectivite mobile Samsung. Peut etre arrete si aucun telephone n'est requis." }
    "service:ss_conn_service2" { return "Connectivite mobile Samsung V2. Peut etre arrete si aucun telephone n'est requis." }
    "service:spooler" { return "Impression Windows. Peut etre coupe si tu n'imprimes pas pendant la session." }
    "service:delltechhub" { return "Service Dell. Candidat a l'arret temporaire si tu veux limiter les outils constructeur." }
    "service:supportassistagent" { return "Dell SupportAssist. Peut lancer diagnostics ou controles en arriere-plan." }
    "service:optionsplusupdaterservice" { return "Mise a jour Logitech Options. Peu utile pendant une session audio." }
    "service:vmcompute" { return "Hyper-V. A couper seulement si Docker, WSL ou machines virtuelles ne servent pas pendant la session." }
    "service:wslservice" { return "WSL. A couper seulement si aucun outil Linux/Dev n'est necessaire pendant la session." }
    "service:hns" { return "Reseau hote Windows pour WSL/Hyper-V/Docker. A couper seulement si ces outils ne servent pas." }
    "process:onedrive" { return "Synchronisation Microsoft OneDrive. Peut consommer disque, reseau et CPU." }
    "process:cloud-drive-daemon" { return "Synology Drive. Peut synchroniser en arriere-plan et charger le disque/reseau." }
    "process:cloud-drive-ui" { return "Interface Synology Drive. A fermer avec le daemon si tu coupes la synchro." }
    "process:phoneexperiencehost" { return "Application Lien avec Windows / telephone. Inutile pour la plupart des sessions audio." }
    "process:crossdeviceservice" { return "Service d'experience multi-appareils Windows. Peut etre ferme si le telephone n'est pas utile." }
    "process:crossdeviceresume" { return "Reprise multi-appareils Windows. Peu utile en session audio." }
    "process:logioptionsplus_agent" { return "Agent Logitech Options. A tester si tes raccourcis souris/clavier ne sont pas critiques." }
    "process:chatgpt" { return "Application ChatGPT. Peut consommer beaucoup de memoire/CPU si ouverte." }
    "process:codex" { return "Application Codex. A fermer seulement si tu n'en as pas besoin pendant la session." }
    "network:tailscale" { return "Adaptateur reseau Tailscale. Le desactiver isole ce tunnel pendant la session." }
    "network:nordlynx" { return "Adaptateur NordVPN WireGuard. A desactiver si tu veux eviter le VPN." }
    "network:connexion au réseau local" { return "Adaptateur TAP OpenVPN. Peut etre desactive si aucun VPN OpenVPN n'est requis." }
    "network:connexion au réseau local 2" { return "Adaptateur TAP NordVPN. Peut etre desactive si aucun VPN NordVPN n'est requis." }
    "network:openvpn connect dco adapter" { return "Adaptateur OpenVPN DCO. Peut etre desactive si aucun VPN OpenVPN n'est requis." }
    "network:openvpn data channel offload for nordvpn" { return "Adaptateur NordVPN DCO. Peut etre desactive si aucun VPN NordVPN n'est requis." }
    "network:connexion réseau bluetooth 2" { return "Reseau Bluetooth. Peut etre desactive si aucun partage reseau Bluetooth n'est requis." }
    default { return "" }
  }
}

function Get-RecommendationRisk {
  param(
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $key = "$Kind`:$Name".ToLowerInvariant()
  switch ($key) {
    "service:vmcompute" { return "Attention" }
    "service:wslservice" { return "Attention" }
    "service:hns" { return "Attention" }
    "service:usosvc" { return "Attention" }
    "service:wuauserv" { return "Attention" }
    "process:chatgpt" { return "Attention" }
    "process:codex" { return "Attention" }
    "network:tailscale" { return "Attention" }
    "network:nordlynx" { return "Attention" }
    default { return "Prudent" }
  }
}

function Get-EntryRisk {
  param(
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][object]$Entry
  )

  $risk = [string](Get-Prop -InputObject $Entry -Name "risk" -Default "")
  if (-not [string]::IsNullOrWhiteSpace($risk)) { return $risk }

  $name = [string](Get-Prop -InputObject $Entry -Name "name" -Default "")
  return Get-RecommendationRisk -Kind $Kind -Name $name
}

function Get-EntryTooltipText {
  param(
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][object]$Entry
  )

  $name = [string](Get-Prop -InputObject $Entry -Name "name" -Default "")
  $displayName = [string](Get-Prop -InputObject $Entry -Name "displayName" -Default "")
  $description = [string](Get-Prop -InputObject $Entry -Name "description" -Default "")
  if ([string]::IsNullOrWhiteSpace($description)) {
    $description = Get-RecommendationDescription -Kind $Kind -Name $name
  }
  if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $name }

  switch ($Kind) {
    "app" {
      $category = [string](Get-Prop -InputObject $Entry -Name "category" -Default "Divers")
      $path = [string](Get-Prop -InputObject $Entry -Name "path" -Default "")
      if ([string]::IsNullOrWhiteSpace($description)) { $description = "Logiciel lance au demarrage de la session audio." }
      $risk = Get-EntryRisk -Kind $Kind -Entry $Entry
      return "$displayName`nCategorie : $category`nPrudence : $risk`n$description`nChemin : $path"
    }
    "service" {
      $action = [string](Get-Prop -InputObject $Entry -Name "action" -Default "Stop")
      if ([string]::IsNullOrWhiteSpace($description)) { $description = "Service Windows gere pendant la session audio." }
      $risk = Get-EntryRisk -Kind $Kind -Entry $Entry
      return "$displayName`nService : $name`nAction : $action`nPrudence : $risk`n$description`nRestauration : retour a l'etat precedent si possible."
    }
    "process" {
      if ([string]::IsNullOrWhiteSpace($description)) { $description = "Processus ferme pendant la session audio." }
      $risk = Get-EntryRisk -Kind $Kind -Entry $Entry
      return "$displayName`nProcessus : $name`nAction : fermer`nPrudence : $risk`n$description`nRestauration : relance si le processus etait ouvert avant."
    }
    "network" {
      $action = [string](Get-Prop -InputObject $Entry -Name "action" -Default "Disable")
      if ([string]::IsNullOrWhiteSpace($description)) { $description = "Adaptateur reseau gere pendant la session audio." }
      $risk = Get-EntryRisk -Kind $Kind -Entry $Entry
      $keep = if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $Entry -Name "audioKeep" -Default $false) }) -Default $false) { "oui" } else { "non" }
      return "$displayName`nAdaptateur : $name`nAction : $action`nPrudence : $risk`nCarte audio a conserver : $keep`n$description`nRestauration : retour a l'etat precedent."
    }
  }

  return $displayName
}

# Sauvegarde l'etat avant session pour pouvoir revenir proprement en arriere.
function Save-EnvironmentState {
  param([Parameter(Mandatory=$true)][object]$Config)

  if (Test-Path -LiteralPath $StatePath) {
    Write-Log "Etat precedent deja sauvegarde, conservation : $StatePath"
    return
  }

  $services = @()
  foreach ($serviceConfig in (Get-ManagedServiceConfigs -Config $Config)) {
    if (-not (Test-EntryEnabled -Entry $serviceConfig -Default $true)) { continue }

    $serviceName = [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($serviceName)) { continue }

    try {
      $svc = Get-Service -Name $serviceName -ErrorAction Stop
      $services += [ordered]@{
        name = $serviceName
        displayName = [string](Get-Prop -InputObject $serviceConfig -Name "displayName" -Default $svc.DisplayName)
        status = $svc.Status.ToString()
        startType = $svc.StartType.ToString()
      }
    } catch {
      $services += [ordered]@{
        name = $serviceName
        displayName = [string](Get-Prop -InputObject $serviceConfig -Name "displayName" -Default $serviceName)
        status = "NotFound"
        startType = "Unknown"
      }
    }
  }

  $processes = @()
  foreach ($processConfig in (Get-ManagedProcessConfigs -Config $Config)) {
    if (-not (Test-EntryEnabled -Entry $processConfig -Default $false)) { continue }

    $processName = [string](Get-Prop -InputObject $processConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($processName)) { continue }

    $runningProcesses = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
    $processes += [ordered]@{
      name = $processName
      displayName = [string](Get-Prop -InputObject $processConfig -Name "displayName" -Default $processName)
      wasRunning = ($runningProcesses.Count -gt 0)
      paths = @($runningProcesses | ForEach-Object {
        try { $_.Path } catch { $null }
      } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    }
  }

  $networkAdapters = @()
  foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
    if (-not (Test-EntryEnabled -Entry $adapterConfig -Default $false)) { continue }

    $adapterName = [string](Get-Prop -InputObject $adapterConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($adapterName)) { continue }

    try {
      $adapter = Get-NetAdapter -Name $adapterName -ErrorAction Stop
      $networkAdapters += [ordered]@{
        name = $adapterName
        displayName = [string](Get-Prop -InputObject $adapterConfig -Name "displayName" -Default $adapter.InterfaceDescription)
        status = $adapter.Status.ToString()
      }
    } catch {
      $networkAdapters += [ordered]@{
        name = $adapterName
        displayName = [string](Get-Prop -InputObject $adapterConfig -Name "displayName" -Default $adapterName)
        status = "NotFound"
      }
    }
  }

  $state = [pscustomobject][ordered]@{
    savedAt = (Get-Date).ToString("s")
    activePowerSchemeGuid = Get-ActivePowerSchemeGuid
    hibernateEnabled = Get-HibernateEnabled
    services = $services
    processes = $processes
    networkAdapters = $networkAdapters
    windowsSecurity = Get-WindowsSecurityState
  }

  $json = $state | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($StatePath, $json + [Environment]::NewLine, (New-Utf8NoBomEncoding))
  Write-Log "Etat precedent sauvegarde : $StatePath"
}

# Restaure le plan d'alimentation, l'hibernation et l'etat initial des services geres.
function Restore-Environment {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    Write-Log "Aucun etat precedent trouve : $StatePath"
    return
  }

  $state = (Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8) | ConvertFrom-Json
  $schemeGuid = [string](Get-Prop -InputObject $state -Name "activePowerSchemeGuid" -Default "")
  if (-not [string]::IsNullOrWhiteSpace($schemeGuid)) {
    Write-Log "Restauration du plan d'alimentation : $schemeGuid"
    & $PowerCfg -setactive $schemeGuid | Out-Null
  }

  $hibernateEnabled = Get-Prop -InputObject $state -Name "hibernateEnabled" -Default $null
  if ($null -ne $hibernateEnabled) {
    if ([int]$hibernateEnabled -eq 1) {
      Write-Log "Restauration hibernation : activee"
      & $PowerCfg -hibernate on | Out-Null
    } else {
      Write-Log "Restauration hibernation : desactivee"
      & $PowerCfg -hibernate off | Out-Null
    }
  }

  foreach ($savedService in (ConvertTo-Array (Get-Prop -InputObject $state -Name "services" -Default @()))) {
    $serviceName = Repair-KnownEncodingIssues -Text ([string](Get-Prop -InputObject $savedService -Name "name" -Default ""))
    $status = [string](Get-Prop -InputObject $savedService -Name "status" -Default "")
    if ([string]::IsNullOrWhiteSpace($serviceName)) { continue }

    try {
      $svc = Get-Service -Name $serviceName -ErrorAction Stop
      if ($status -eq "Running" -and $svc.Status -ne "Running") {
        Start-ServiceWithTimeout -ServiceName $serviceName -Label $serviceName
      } elseif ($status -eq "Stopped" -and $svc.Status -eq "Running") {
        Stop-ServiceWithTimeout -ServiceName $serviceName -Label $serviceName
      }
    } catch {
      Write-Log "Service non restaure : $serviceName ($($_.Exception.Message))"
    }
  }

  foreach ($savedAdapter in (ConvertTo-Array (Get-Prop -InputObject $state -Name "networkAdapters" -Default @()))) {
    $adapterName = Repair-KnownEncodingIssues -Text ([string](Get-Prop -InputObject $savedAdapter -Name "name" -Default ""))
    $status = [string](Get-Prop -InputObject $savedAdapter -Name "status" -Default "")
    if ([string]::IsNullOrWhiteSpace($adapterName)) { continue }

    try {
      $adapter = Get-NetAdapter -Name $adapterName -ErrorAction Stop
      if ($status -eq "Up" -and $adapter.Status -ne "Up") {
        Write-Log "Reactivation de l'adaptateur reseau : $adapterName"
        Enable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
      } elseif (($status -eq "Disabled" -or $status -eq "Not Present") -and $adapter.Status -ne "Disabled") {
        Write-Log "Desactivation restauree de l'adaptateur reseau : $adapterName"
        Disable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
      }
    } catch {
      Write-Log "Adaptateur reseau non restaure : $adapterName ($($_.Exception.Message))"
    }
  }

  foreach ($savedProcess in (ConvertTo-Array (Get-Prop -InputObject $state -Name "processes" -Default @()))) {
    $processName = Repair-KnownEncodingIssues -Text ([string](Get-Prop -InputObject $savedProcess -Name "name" -Default ""))
    $wasRunning = Get-Prop -InputObject $savedProcess -Name "wasRunning" -Default $false
    if ([string]::IsNullOrWhiteSpace($processName)) { continue }
    if (-not [System.Convert]::ToBoolean($wasRunning)) { continue }
    if (Get-Process -Name $processName -ErrorAction SilentlyContinue) { continue }

    $paths = @(ConvertTo-Array (Get-Prop -InputObject $savedProcess -Name "paths" -Default @()))
    $pathToStart = $paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($pathToStart) {
      try {
        Write-Log "Relance du processus : $processName"
        Start-Process -FilePath $pathToStart | Out-Null
      } catch {
        Write-Log "Processus non relance : $processName ($($_.Exception.Message))"
      }
    }
  }

  Restore-WindowsSecurityState -State $state

  Write-Log "Restauration terminee"
  try { Remove-Item -LiteralPath $StatePath -Force -ErrorAction Stop } catch {}
}

# Actions service : arreter ou demarrer selon le choix dans l'onglet Services.
function Wait-ServiceStatus {
  param(
    [Parameter(Mandatory=$true)][string]$ServiceName,
    [Parameter(Mandatory=$true)][string]$TargetStatus,
    [int]$TimeoutSeconds = 15
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try {
      $svc = Get-Service -Name $ServiceName -ErrorAction Stop
      if ($svc.Status.ToString() -eq $TargetStatus) { return $true }
    } catch {
      return $false
    }

    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return $false
}

function Start-ServiceWithTimeout {
  param(
    [Parameter(Mandatory=$true)][string]$ServiceName,
    [Parameter(Mandatory=$true)][string]$Label,
    [int]$TimeoutSeconds = 15
  )

  try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
  } catch {
    Write-Log "Service introuvable : $Label ($ServiceName). Rien a faire."
    return
  }

  if ($svc.Status -eq "Running") {
    Write-Log "Service deja demarre : $Label ($ServiceName)"
    return
  }

  Write-Log "Demarrage du service : $Label ($ServiceName)"
  try {
    & $ScExe start $ServiceName | Out-Null
  } catch {
    Write-Log "Demarrage impossible : $Label ($ServiceName) - $($_.Exception.Message)"
    return
  }

  if (-not (Wait-ServiceStatus -ServiceName $ServiceName -TargetStatus "Running" -TimeoutSeconds $TimeoutSeconds)) {
    Write-Log "Delai depasse au demarrage du service : $Label ($ServiceName). On continue."
  }
}

function Stop-ServiceWithTimeout {
  param(
    [Parameter(Mandatory=$true)][string]$ServiceName,
    [Parameter(Mandatory=$true)][string]$Label,
    [int]$TimeoutSeconds = 15
  )

  try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
  } catch {
    Write-Log "Service introuvable : $Label ($ServiceName). Rien a faire."
    return
  }

  if ($svc.Status -eq "Stopped") {
    Write-Log "Service deja arrete : $Label ($ServiceName)"
    return
  }

  Write-Log "Arret du service : $Label ($ServiceName)"
  try {
    & $ScExe stop $ServiceName | Out-Null
  } catch {
    Write-Log "Arret impossible : $Label ($ServiceName) - $($_.Exception.Message)"
    return
  }

  if (-not (Wait-ServiceStatus -ServiceName $ServiceName -TargetStatus "Stopped" -TimeoutSeconds $TimeoutSeconds)) {
    Write-Log "Delai depasse a l'arret du service : $Label ($ServiceName). On continue."
  }
}

function Ensure-ServiceStopped {
  param([Parameter(Mandatory=$true)][object]$ServiceConfig)

  $serviceName = [string](Get-Prop -InputObject $ServiceConfig -Name "name" -Default "")
  if ([string]::IsNullOrWhiteSpace($serviceName)) { return }

  $label = [string](Get-Prop -InputObject $ServiceConfig -Name "displayName" -Default $serviceName)
  Stop-ServiceWithTimeout -ServiceName $serviceName -Label $label
}

function Ensure-ServiceStarted {
  param([Parameter(Mandatory=$true)][object]$ServiceConfig)

  $serviceName = [string](Get-Prop -InputObject $ServiceConfig -Name "name" -Default "")
  if ([string]::IsNullOrWhiteSpace($serviceName)) { return }

  $label = [string](Get-Prop -InputObject $ServiceConfig -Name "displayName" -Default $serviceName)
  Start-ServiceWithTimeout -ServiceName $serviceName -Label $label
}

function Apply-ServiceAction {
  param([Parameter(Mandatory=$true)][object]$ServiceConfig)

  $action = [string](Get-Prop -InputObject $ServiceConfig -Name "action" -Default "Stop")
  switch ($action.ToLowerInvariant()) {
    "start" { Ensure-ServiceStarted -ServiceConfig $ServiceConfig }
    "demarrer" { Ensure-ServiceStarted -ServiceConfig $ServiceConfig }
    default { Ensure-ServiceStopped -ServiceConfig $ServiceConfig }
  }
}

function Close-ManagedProcess {
  param([Parameter(Mandatory=$true)][object]$ProcessConfig)

  $processName = [string](Get-Prop -InputObject $ProcessConfig -Name "name" -Default "")
  if ([string]::IsNullOrWhiteSpace($processName)) { return }

  $label = [string](Get-Prop -InputObject $ProcessConfig -Name "displayName" -Default $processName)
  $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
  if ($processes.Count -eq 0) {
    Write-Log "Processus deja ferme : $label ($processName)"
    return
  }

  Write-Log "Fermeture du processus : $label ($processName)"
  foreach ($process in $processes) {
    try {
      if ($process.MainWindowHandle -ne 0) {
        [void]$process.CloseMainWindow()
      }
    } catch {}
  }

  Start-Sleep -Seconds 3
  foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    try {
      Write-Log "Arret force du processus restant : $processName ($($process.Id))"
      Stop-Process -Id $process.Id -Force -ErrorAction Stop
    } catch {
      Write-Log "Processus non ferme : $processName ($($_.Exception.Message))"
    }
  }
}

function Apply-NetworkAdapterAction {
  param([Parameter(Mandatory=$true)][object]$AdapterConfig)

  $adapterName = [string](Get-Prop -InputObject $AdapterConfig -Name "name" -Default "")
  if ([string]::IsNullOrWhiteSpace($adapterName)) { return }

  $label = [string](Get-Prop -InputObject $AdapterConfig -Name "displayName" -Default $adapterName)
  $action = [string](Get-Prop -InputObject $AdapterConfig -Name "action" -Default "Disable")
  $audioKeep = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $AdapterConfig -Name "audioKeep" -Default $false) }) -Default $false

  try {
    $adapter = Get-NetAdapter -Name $adapterName -ErrorAction Stop
  } catch {
    Write-Log "Adaptateur reseau introuvable : $label ($adapterName)"
    return
  }

  if ($action.ToLowerInvariant() -eq "enable") {
    if ($adapter.Status -eq "Disabled") {
      Write-Log "Activation de l'adaptateur reseau : $label ($adapterName)"
      Enable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
    } else {
      Write-Log "Adaptateur reseau deja actif : $label ($adapterName)"
    }
  } else {
    if ($audioKeep) {
      Write-Log "Carte reseau conservee pour l'audio, desactivation ignoree : $label ($adapterName)"
      return
    }

    if ($adapter.Status -ne "Disabled") {
      Write-Log "Desactivation de l'adaptateur reseau : $label ($adapterName)"
      Disable-NetAdapter -Name $adapterName -Confirm:$false -ErrorAction Stop
    } else {
      Write-Log "Adaptateur reseau deja desactive : $label ($adapterName)"
    }
  }
}

# Active le plan choisi, en important Mode_Audio.pow si le plan n'existe pas encore.
function Ensure-AudioPowerPlan {
  param([Parameter(Mandatory=$true)][object]$Config)

  $plan = Get-Prop -InputObject $Config -Name "audioPlan" -Default $null
  $planName = [string](Get-Prop -InputObject $plan -Name "name" -Default "Mode Audio")
  $expectedGuid = [string](Get-Prop -InputObject $plan -Name "expectedGuid" -Default "")
  $powFile = [string](Get-Prop -InputObject $plan -Name "powFile" -Default "Mode_Audio.pow")
  $powPath = Resolve-SessionPath -Path $powFile

  Write-Log "Verification du plan d'alimentation : $planName"
  $guid = Get-PlanGuidByName -PlanName $planName

  if (-not $guid) {
    Write-Log "Plan introuvable. Import depuis : $powPath"
    if (-not (Test-Path -LiteralPath $powPath)) {
      throw "Fichier POW introuvable : $powPath"
    }

    & $PowerCfg -import "$powPath" | Out-Null
    Start-Sleep -Seconds 1
    $guid = Get-PlanGuidByName -PlanName $planName
    if (-not $guid) {
      throw "Plan '$planName' introuvable apres import."
    }
  }

  if ($expectedGuid -and ($guid -ne $expectedGuid)) {
    Write-Log "Note : GUID du plan different de la valeur attendue. Actuel : $guid"
  }

  Write-Log "Activation du plan : $guid"
  & $PowerCfg -setactive $guid | Out-Null

  Write-Log "Verrouillage veille et affichage"
  & $PowerCfg -change -monitor-timeout-ac 0 | Out-Null
  & $PowerCfg -change -monitor-timeout-dc 0 | Out-Null
  & $PowerCfg -change -standby-timeout-ac 0 | Out-Null
  & $PowerCfg -change -standby-timeout-dc 0 | Out-Null
  & $PowerCfg -hibernate off | Out-Null

  $active = & $PowerCfg -getactivescheme 2>$null
  Write-Log "Plan actif confirme : $active"

  return $guid
}

function Set-PlanValueIndex {
  param(
    [Parameter(Mandatory=$true)][string]$SchemeGuid,
    [Parameter(Mandatory=$true)][string]$SubGroupGuid,
    [Parameter(Mandatory=$true)][string]$SettingGuid,
    [Parameter(Mandatory=$true)][int]$Value,
    [Parameter(Mandatory=$true)][ValidateSet("AC","DC")][string]$PowerSource
  )

  if ($PowerSource -eq "AC") {
    & $PowerCfg -setacvalueindex $SchemeGuid $SubGroupGuid $SettingGuid $Value | Out-Null
  } else {
    & $PowerCfg -setdcvalueindex $SchemeGuid $SubGroupGuid $SettingGuid $Value | Out-Null
  }
}

# Applique les reglages audio Windows qui evitent les mises en veille et economies USB/CPU.
function Enforce-CPUAndUSBSettings {
  param([Parameter(Mandatory=$true)][string]$SchemeGuid)

  $SubProc = "54533251-82be-4824-96c1-47b60b740d00"
  $MinProc = "893dee8e-2bef-41e0-89c6-b55d0929964c"
  $MaxProc = "bc5038f7-23e0-4960-96da-33abaf5935ec"

  Write-Log "Forcage CPU min/max a 100 % (secteur et batterie)"
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubProc -SettingGuid $MinProc -Value 100 -PowerSource AC
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubProc -SettingGuid $MaxProc -Value 100 -PowerSource AC
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubProc -SettingGuid $MinProc -Value 100 -PowerSource DC
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubProc -SettingGuid $MaxProc -Value 100 -PowerSource DC

  $SubUSB = "2a737441-1930-4402-8d77-b2bebba308a3"
  $UsbSelectiveSuspend = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
  $Usb3LinkPowerMgmt = "d4e98f31-5ffe-4ce1-be31-1b38b384c009"

  Write-Log "Desactivation suspension selective USB (secteur et batterie)"
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubUSB -SettingGuid $UsbSelectiveSuspend -Value 0 -PowerSource AC
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubUSB -SettingGuid $UsbSelectiveSuspend -Value 0 -PowerSource DC

  Write-Log "Gestion energie USB 3 Link Power Management : Off (secteur et batterie)"
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubUSB -SettingGuid $Usb3LinkPowerMgmt -Value 0 -PowerSource AC
  Set-PlanValueIndex -SchemeGuid $SchemeGuid -SubGroupGuid $SubUSB -SettingGuid $Usb3LinkPowerMgmt -Value 0 -PowerSource DC

  & $PowerCfg -setactive $SchemeGuid | Out-Null
}

function Get-DefaultAppDelaySeconds {
  param([Parameter(Mandatory=$true)][string]$AppName)

  switch ($AppName) {
    "Total Mix 1"           { return 2 }
    "Total Mix 2"           { return 2 }
    "Dante Controller"      { return 4 }
    "Voicemeeter Banana"    { return 6 }
    "Milan Manager"         { return 6 }
    "AgoraController"       { return 4 }
    "Loop Midi"             { return 4 }
    "N.O.D.E"               { return 10 }
    default                 { return 1 }
  }
}

function Get-AppDelaySeconds {
  param([Parameter(Mandatory=$true)][object]$App)

  $appName = [string](Get-Prop -InputObject $App -Name "name" -Default "")
  $delay = Get-Prop -InputObject $App -Name "delaySeconds" -Default $null
  if ($null -ne $delay) {
    try { return [Math]::Max(0, [int]$delay) } catch {}
  }

  return Get-DefaultAppDelaySeconds -AppName $appName
}

function Start-AppIfNotRunning {
  param([Parameter(Mandatory=$true)][object]$App)

  $appName = [string](Get-Prop -InputObject $App -Name "name" -Default "")
  $rawPath = [string](Get-Prop -InputObject $App -Name "path" -Default "")

  if ([string]::IsNullOrWhiteSpace($appName)) { $appName = "Application sans nom" }
  if ([string]::IsNullOrWhiteSpace($rawPath)) {
    Write-Log "Chemin vide : $appName"
    return $false
  }

  $launchPath = Resolve-SessionPath -Path $rawPath
  if (-not (Test-Path -LiteralPath $launchPath)) {
    Write-Log "Chemin introuvable : $appName -> $launchPath"
    return $false
  }

  $extension = [System.IO.Path]::GetExtension($launchPath).ToLowerInvariant()
  if ($extension -eq ".exe") {
    $procName = [System.IO.Path]::GetFileNameWithoutExtension($launchPath)
    $alreadyRunning = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($alreadyRunning) {
      Write-Log "$appName deja lance"
      return $false
    }
  }

  $workingDirectory = Split-Path -Parent $launchPath
  Write-Log "Lancement : $appName"

  if ($extension -eq ".ps1") {
    $psExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $psExe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$launchPath`"") -WorkingDirectory $workingDirectory | Out-Null
  } else {
    Start-Process -FilePath $launchPath -WorkingDirectory $workingDirectory | Out-Null
  }

  return $true
}

function Get-EnabledApps {
  param([Parameter(Mandatory=$true)][object]$Config)

  $enabledApps = @()
  foreach ($app in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "apps" -Default @()))) {
    if (Test-EntryEnabled -Entry $app -Default $false) {
      $enabledApps += $app
    }
  }
  return $enabledApps
}

# Fenetre d'ajout de logiciels : exe, raccourcis et scripts.
function Add-AppsFromDialog {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [object]$Owner = $null
  )

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName Microsoft.VisualBasic

  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = "Ajouter un logiciel"
  $dialog.Filter = "Programmes et raccourcis|*.exe;*.lnk;*.bat;*.cmd;*.ps1|Tous les fichiers|*.*"
  $dialog.Multiselect = $true

  $result = if ($Owner) { $dialog.ShowDialog($Owner) } else { $dialog.ShowDialog() }
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

  $category = [Microsoft.VisualBasic.Interaction]::InputBox("Categorie", "Ajouter", "Divers")
  if ([string]::IsNullOrWhiteSpace($category)) { $category = "Divers" }

  $delayText = [Microsoft.VisualBasic.Interaction]::InputBox("Pause apres lancement, en secondes", "Ajouter", "0")
  $delaySeconds = 0
  [void][int]::TryParse($delayText, [ref]$delaySeconds)
  if ($delaySeconds -lt 0) { $delaySeconds = 0 }

  $apps = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "apps" -Default @()))
  foreach ($fileName in $dialog.FileNames) {
    $apps += [pscustomobject][ordered]@{
      name = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
      category = $category
      path = $fileName
      delaySeconds = $delaySeconds
      enabled = $true
    }
  }

  Set-Prop -InputObject $Config -Name "apps" -Value $apps
  Save-Config -Config $Config
  return $true
}

# Fenetre d'ajout de services Windows avec choix Arreter/Demarrer.
function Add-ServiceFromDialog {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [object]$Owner = $null
  )

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "Ajouter un service"
  $dialog.StartPosition = "CenterParent"
  $dialog.Size = New-Object System.Drawing.Size(620, 170)
  $dialog.FormBorderStyle = "FixedDialog"
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $layout = New-Object System.Windows.Forms.TableLayoutPanel
  $layout.Dock = "Fill"
  $layout.ColumnCount = 2
  $layout.RowCount = 3
  $layout.Padding = New-Object System.Windows.Forms.Padding(10)
  [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
  [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))

  $serviceLabel = New-Object System.Windows.Forms.Label
  $serviceLabel.Text = "Service"
  $serviceLabel.Dock = "Fill"
  $serviceLabel.TextAlign = "MiddleLeft"

  $serviceComboBox = New-Object System.Windows.Forms.ComboBox
  $serviceComboBox.Dock = "Fill"
  $serviceComboBox.DropDownStyle = "DropDown"
  $serviceComboBox.AutoCompleteMode = "SuggestAppend"
  $serviceComboBox.AutoCompleteSource = "ListItems"
  $serviceComboBox.DisplayMember = "label"

  $installedServices = @(Get-Service | Sort-Object DisplayName)
  foreach ($svc in $installedServices) {
    [void]$serviceComboBox.Items.Add([pscustomobject][ordered]@{
      name = $svc.Name
      displayName = $svc.DisplayName
      label = "$($svc.DisplayName) ($($svc.Name))"
    })
  }

  $actionLabel = New-Object System.Windows.Forms.Label
  $actionLabel.Text = "Action"
  $actionLabel.Dock = "Fill"
  $actionLabel.TextAlign = "MiddleLeft"

  $actionComboBox = New-Object System.Windows.Forms.ComboBox
  $actionComboBox.Dock = "Fill"
  $actionComboBox.DropDownStyle = "DropDownList"
  [void]$actionComboBox.Items.Add("Arreter")
  [void]$actionComboBox.Items.Add("Demarrer")
  $actionComboBox.SelectedIndex = 0

  $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
  $buttonPanel.Dock = "Fill"
  $buttonPanel.FlowDirection = "RightToLeft"

  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Text = "Ajouter"
  $okButton.Width = 90

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Text = "Annuler"
  $cancelButton.Width = 90

  [void]$buttonPanel.Controls.Add($okButton)
  [void]$buttonPanel.Controls.Add($cancelButton)

  [void]$layout.Controls.Add($serviceLabel, 0, 0)
  [void]$layout.Controls.Add($serviceComboBox, 1, 0)
  [void]$layout.Controls.Add($actionLabel, 0, 1)
  [void]$layout.Controls.Add($actionComboBox, 1, 1)
  [void]$layout.Controls.Add($buttonPanel, 1, 2)
  [void]$dialog.Controls.Add($layout)

  $okButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($serviceComboBox.Text)) { return }
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $cancelButton.Add_Click({
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Close()
  })
  $dialog.AcceptButton = $okButton
  $dialog.CancelButton = $cancelButton

  $result = if ($Owner) { $dialog.ShowDialog($Owner) } else { $dialog.ShowDialog() }
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

  $selectedService = $serviceComboBox.SelectedItem
  if ($selectedService) {
    $serviceName = [string]$selectedService.name
    $displayName = [string]$selectedService.displayName
  } else {
    $serviceName = $serviceComboBox.Text.Trim()
    $displayName = $serviceName
  }

  $action = if ([string]$actionComboBox.SelectedItem -eq "Demarrer") { "Start" } else { "Stop" }
  $services = @(Get-ManagedServiceConfigs -Config $Config)
  $services += [pscustomobject][ordered]@{
    name = $serviceName
    displayName = $displayName
    action = $action
    enabled = $true
  }

  Set-Prop -InputObject $Config -Name "services" -Value $services
  Save-Config -Config $Config
  return $true
}

function Add-ProcessFromDialog {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [object]$Owner = $null
  )

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName Microsoft.VisualBasic

  $dialog = New-Object System.Windows.Forms.OpenFileDialog
  $dialog.Title = "Ajouter un processus a fermer"
  $dialog.Filter = "Programmes|*.exe|Tous les fichiers|*.*"
  $dialog.Multiselect = $true

  $result = if ($Owner) { $dialog.ShowDialog($Owner) } else { $dialog.ShowDialog() }
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

  $processes = @(Get-ManagedProcessConfigs -Config $Config)
  foreach ($fileName in $dialog.FileNames) {
    $processes += [pscustomobject][ordered]@{
      name = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
      displayName = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
      action = "Close"
      path = $fileName
      enabled = $true
    }
  }

  Set-Prop -InputObject $Config -Name "processes" -Value $processes
  Save-Config -Config $Config
  return $true
}

function Add-NetworkAdapterFromDialog {
  param(
    [Parameter(Mandatory=$true)][object]$Config,
    [object]$Owner = $null
  )

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = "Ajouter un adaptateur reseau"
  $dialog.StartPosition = "CenterParent"
  $dialog.Size = New-Object System.Drawing.Size(620, 170)
  $dialog.FormBorderStyle = "FixedDialog"
  $dialog.MaximizeBox = $false
  $dialog.MinimizeBox = $false

  $layout = New-Object System.Windows.Forms.TableLayoutPanel
  $layout.Dock = "Fill"
  $layout.ColumnCount = 2
  $layout.RowCount = 3
  $layout.Padding = New-Object System.Windows.Forms.Padding(10)
  [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 100)))
  [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

  $adapterLabel = New-Object System.Windows.Forms.Label
  $adapterLabel.Text = "Adaptateur"
  $adapterLabel.Dock = "Fill"
  $adapterLabel.TextAlign = "MiddleLeft"

  $adapterComboBox = New-Object System.Windows.Forms.ComboBox
  $adapterComboBox.Dock = "Fill"
  $adapterComboBox.DropDownStyle = "DropDownList"
  $adapterComboBox.DisplayMember = "label"

  foreach ($adapter in @(Get-NetAdapter | Sort-Object Name)) {
    [void]$adapterComboBox.Items.Add([pscustomobject][ordered]@{
      name = $adapter.Name
      displayName = $adapter.InterfaceDescription
      label = "$($adapter.Name) - $($adapter.InterfaceDescription)"
    })
  }
  if ($adapterComboBox.Items.Count -gt 0) { $adapterComboBox.SelectedIndex = 0 }

  $actionLabel = New-Object System.Windows.Forms.Label
  $actionLabel.Text = "Action"
  $actionLabel.Dock = "Fill"
  $actionLabel.TextAlign = "MiddleLeft"

  $actionComboBox = New-Object System.Windows.Forms.ComboBox
  $actionComboBox.Dock = "Fill"
  $actionComboBox.DropDownStyle = "DropDownList"
  [void]$actionComboBox.Items.Add("Desactiver")
  [void]$actionComboBox.Items.Add("Activer")
  $actionComboBox.SelectedIndex = 0

  $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
  $buttonPanel.Dock = "Fill"
  $buttonPanel.FlowDirection = "RightToLeft"
  $okButton = New-Object System.Windows.Forms.Button
  $okButton.Text = "Ajouter"
  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Text = "Annuler"
  [void]$buttonPanel.Controls.Add($okButton)
  [void]$buttonPanel.Controls.Add($cancelButton)

  [void]$layout.Controls.Add($adapterLabel, 0, 0)
  [void]$layout.Controls.Add($adapterComboBox, 1, 0)
  [void]$layout.Controls.Add($actionLabel, 0, 1)
  [void]$layout.Controls.Add($actionComboBox, 1, 1)
  [void]$layout.Controls.Add($buttonPanel, 1, 2)
  [void]$dialog.Controls.Add($layout)

  $okButton.Add_Click({
    if ($null -eq $adapterComboBox.SelectedItem) { return }
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Close()
  })
  $cancelButton.Add_Click({
    $dialog.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Close()
  })

  $result = if ($Owner) { $dialog.ShowDialog($Owner) } else { $dialog.ShowDialog() }
  if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

  $selectedAdapter = $adapterComboBox.SelectedItem
  $action = if ([string]$actionComboBox.SelectedItem -eq "Activer") { "Enable" } else { "Disable" }
  $adapters = @(Get-ManagedNetworkAdapterConfigs -Config $Config)
  $adapters += [pscustomobject][ordered]@{
    name = [string]$selectedAdapter.name
    displayName = [string]$selectedAdapter.displayName
    action = $action
    enabled = $true
  }

  Set-Prop -InputObject $Config -Name "networkAdapters" -Value $adapters
  Save-Config -Config $Config
  return $true
}

function Get-DiagnosticReportLines {
  param([Parameter(Mandatory=$true)][object]$Config)

  $lines = @()
  $lines += "=== DIAGNOSTIC SESSION AUDIO ==="
  $lines += "Date : " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  $lines += ""

  try {
    $lines += "Plan alimentation actif : " + ((& $PowerCfg -getactivescheme 2>$null) -join " ")
  } catch {
    $lines += "Plan alimentation actif : lecture impossible ($($_.Exception.Message))"
  }

  $securityConfig = Get-WindowsSecurityConfig -Config $Config
  $lines += ""
  $lines += "--- Securite Windows ---"
  $lines += ("Option pare-feu temporairement coupe : {0}" -f (Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableFirewall"))
  $lines += ("Option scan temps reel Defender coupe : {0}" -f (Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableDefenderRealtime"))
  $lines += ("Option taches planifiees Defender suspendues : {0}" -f (Test-WindowsSecurityOptionEnabled -Config $Config -Name "disableDefenderScheduledTasks"))
  $lines += ("Confirmation requise : {0}" -f (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $securityConfig -Name "requireConfirmation" -Default $true) }) -Default $true))
  $firewallState = Get-FirewallProfileState
  if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $firewallState -Name "supported" -Default $false) }) -Default $false) {
    foreach ($profile in (ConvertTo-Array (Get-Prop -InputObject $firewallState -Name "profiles" -Default @()))) {
      $lines += ("Pare-feu {0} : {1}" -f (Get-Prop -InputObject $profile -Name "name" -Default ""), (Get-Prop -InputObject $profile -Name "enabled" -Default "Information indisponible"))
    }
  } else {
    $lines += "Pare-feu : Information indisponible"
  }
  $defenderState = Get-DefenderRealtimeState
  if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $defenderState -Name "supported" -Default $false) }) -Default $false) {
    $lines += ("Defender temps reel desactive : {0}" -f (Get-Prop -InputObject $defenderState -Name "disableRealtimeMonitoring" -Default "Information indisponible"))
  } else {
    $lines += "Defender temps reel : Information indisponible"
  }
  $defenderTasksState = Get-DefenderScheduledTaskState
  if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $defenderTasksState -Name "supported" -Default $false) }) -Default $false) {
    foreach ($task in (ConvertTo-Array (Get-Prop -InputObject $defenderTasksState -Name "tasks" -Default @()))) {
      $lines += ("Tache Defender {0} : {1}" -f (Get-Prop -InputObject $task -Name "taskName" -Default ""), (Get-Prop -InputObject $task -Name "state" -Default "Information indisponible"))
    }
  } else {
    $lines += "Taches planifiees Defender : Information indisponible"
  }

  $lines += ""
  $lines += "--- Services geres ---"
  foreach ($serviceConfig in (Get-ManagedServiceConfigs -Config $Config)) {
    $name = [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    try {
      $svc = Get-Service -Name $name -ErrorAction Stop
      $lines += ("{0} | {1} | StartType={2}" -f $name, $svc.Status, $svc.StartType)
    } catch {
      $lines += "$name | introuvable"
    }
  }

  $lines += ""
  $lines += "--- Processus geres ---"
  foreach ($processConfig in (Get-ManagedProcessConfigs -Config $Config)) {
    $name = [string](Get-Prop -InputObject $processConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($processes.Count -gt 0) {
      $memoryMb = [Math]::Round((($processes | Measure-Object -Property WorkingSet64 -Sum).Sum / 1MB), 1)
      $lines += ("{0} | actif | instances={1} | memoire={2} MB" -f $name, $processes.Count, $memoryMb)
    } else {
      $lines += "$name | absent"
    }
  }

  $lines += ""
  $lines += "--- Cartes reseau gerees ---"
  foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
    $name = [string](Get-Prop -InputObject $adapterConfig -Name "name" -Default "")
    if ([string]::IsNullOrWhiteSpace($name)) { continue }

    try {
      $adapter = Get-NetAdapter -Name $name -ErrorAction Stop
      $audioKeep = if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $adapterConfig -Name "audioKeep" -Default $false) }) -Default $false) { "oui" } else { "non" }
      $lines += ("{0} | {1} | vitesse={2} | conserver audio={3}" -f $adapter.Name, $adapter.Status, $adapter.LinkSpeed, $audioKeep)

      try {
        $advanced = Get-NetAdapterAdvancedProperty -Name $name -ErrorAction Stop |
          Where-Object { $_.DisplayName -match "Flow Control|Interrupt Moderation|Energy Efficient|Green|Speed|Duplex" }
        foreach ($property in $advanced) {
          $lines += ("  - {0} = {1}" -f $property.DisplayName, $property.DisplayValue)
        }
      } catch {
        $lines += "  - parametres avances : lecture impossible"
      }
    } catch {
      $lines += "$name | introuvable"
    }
  }

  $lines += ""
  $lines += "--- Drivers audio / reseau / GPU ---"
  try {
    $drivers = Get-CimInstance Win32_PnPSignedDriver |
      Where-Object { $_.DeviceClass -in @("MEDIA", "NET", "DISPLAY") } |
      Sort-Object DeviceClass, DeviceName
    foreach ($driver in $drivers) {
      $lines += ("{0} | {1} | {2} | {3}" -f $driver.DeviceClass, $driver.DeviceName, $driver.DriverVersion, $driver.DriverDate)
    }
  } catch {
    $lines += "Drivers : lecture impossible ($($_.Exception.Message))"
  }

  $lines += ""
  $lines += "--- BIOS / firmware ---"
  try {
    $bios = Get-CimInstance Win32_BIOS
    $lines += ("BIOS : {0} | version={1} | date={2}" -f $bios.Manufacturer, $bios.SMBIOSBIOSVersion, $bios.ReleaseDate)
  } catch {
    $lines += "BIOS : lecture impossible ($($_.Exception.Message))"
  }

  $lines += "=== FIN DIAGNOSTIC ==="
  return $lines
}

function Write-DiagnosticReport {
  param([Parameter(Mandatory=$true)][object]$Config)

  foreach ($line in (Get-DiagnosticReportLines -Config $Config)) {
    Write-Log $line
  }
}

# Fenetre principale : plan d'alimentation, logiciels, services et restauration.
function Show-AppSelectionDialog {
  param([Parameter(Mandatory=$true)][object]$Config)

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch {}

  $form = New-Object System.Windows.Forms.Form
  $form.Text = "Session Audio - By Mamat"
  $form.StartPosition = "CenterScreen"
  $form.Size = New-Object System.Drawing.Size(1040, 660)
  $form.MinimumSize = New-Object System.Drawing.Size(760, 480)
  if (Test-Path -LiteralPath $IconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($IconPath) } catch {}
  }

  $rowToolTip = New-Object System.Windows.Forms.ToolTip
  $rowToolTip.AutoPopDelay = 12000
  $rowToolTip.InitialDelay = 300
  $rowToolTip.ReshowDelay = 100
  $rowToolTip.ShowAlways = $true
  $script:lastToolTipKey = ""

  $tabControl = New-Object System.Windows.Forms.TabControl
  $tabControl.Dock = "Fill"

  $appsTab = New-Object System.Windows.Forms.TabPage
  $appsTab.Text = "Logiciels"

  $servicesTab = New-Object System.Windows.Forms.TabPage
  $servicesTab.Text = "Services"

  $processesTab = New-Object System.Windows.Forms.TabPage
  $processesTab.Text = "Processus"

  $networkTab = New-Object System.Windows.Forms.TabPage
  $networkTab.Text = "Reseau"

  $securityTab = New-Object System.Windows.Forms.TabPage
  $securityTab.Text = "Securite"

  $diagnosticTab = New-Object System.Windows.Forms.TabPage
  $diagnosticTab.Text = "Diagnostic"

  $topPanel = New-Object System.Windows.Forms.TableLayoutPanel
  $topPanel.Dock = "Top"
  $topPanel.Height = 78
  $topPanel.ColumnCount = 4
  $topPanel.RowCount = 1
  $topPanel.Padding = New-Object System.Windows.Forms.Padding(8)
  [void]$topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
  [void]$topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
  [void]$topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
  [void]$topPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
  $topPanel.RowCount = 2
  [void]$topPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))
  [void]$topPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 31)))

  $powerPlanLabel = New-Object System.Windows.Forms.Label
  $powerPlanLabel.Text = "Plan alimentation"
  $powerPlanLabel.Dock = "Fill"
  $powerPlanLabel.TextAlign = "MiddleLeft"

  $powerPlanComboBox = New-Object System.Windows.Forms.ComboBox
  $powerPlanComboBox.Dock = "Fill"
  $powerPlanComboBox.DropDownStyle = "DropDownList"
  $powerPlanComboBox.DisplayMember = "label"
  $powerPlanComboBox.ValueMember = "guid"

  $refreshPlansButton = New-Object System.Windows.Forms.Button
  $refreshPlansButton.Text = "Actualiser"
  $refreshPlansButton.Dock = "Fill"

  $profileLabel = New-Object System.Windows.Forms.Label
  $profileLabel.Text = "Profil"
  $profileLabel.Dock = "Fill"
  $profileLabel.TextAlign = "MiddleLeft"

  $profileComboBox = New-Object System.Windows.Forms.ComboBox
  $profileComboBox.Dock = "Fill"
  $profileComboBox.DropDownStyle = "DropDownList"
  $profileComboBox.DisplayMember = "name"

  $saveProfileButton = New-Object System.Windows.Forms.Button
  $saveProfileButton.Text = "Sauver profil"
  $saveProfileButton.Width = 90

  $renameProfileButton = New-Object System.Windows.Forms.Button
  $renameProfileButton.Text = "Renommer"
  $renameProfileButton.Width = 85

  $duplicateProfileButton = New-Object System.Windows.Forms.Button
  $duplicateProfileButton.Text = "Dupliquer"
  $duplicateProfileButton.Width = 85

  $deleteProfileButton = New-Object System.Windows.Forms.Button
  $deleteProfileButton.Text = "Supprimer"
  $deleteProfileButton.Width = 90

  $profileActionsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
  $profileActionsPanel.Dock = "Fill"
  $profileActionsPanel.FlowDirection = "LeftToRight"
  $profileActionsPanel.WrapContents = $false
  [void]$profileActionsPanel.Controls.Add($saveProfileButton)
  [void]$profileActionsPanel.Controls.Add($renameProfileButton)
  [void]$profileActionsPanel.Controls.Add($duplicateProfileButton)
  [void]$profileActionsPanel.Controls.Add($deleteProfileButton)

  [void]$topPanel.Controls.Add($powerPlanLabel, 0, 0)
  [void]$topPanel.Controls.Add($powerPlanComboBox, 1, 0)
  [void]$topPanel.Controls.Add($refreshPlansButton, 2, 0)
  [void]$topPanel.SetColumnSpan($refreshPlansButton, 2)
  [void]$topPanel.Controls.Add($profileLabel, 0, 1)
  [void]$topPanel.Controls.Add($profileComboBox, 1, 1)
  [void]$topPanel.Controls.Add($profileActionsPanel, 2, 1)
  [void]$topPanel.SetColumnSpan($profileActionsPanel, 2)

  $list = New-Object System.Windows.Forms.ListView
  $list.Dock = "Fill"
  $list.View = "Details"
  $list.CheckBoxes = $true
  $list.FullRowSelect = $true
  $list.GridLines = $false
  $list.HideSelection = $false
  $list.ShowItemToolTips = $true
  [void]$list.Columns.Add("Categorie", 160)
  [void]$list.Columns.Add("Logiciel", 220)
  [void]$list.Columns.Add("Prudence", 90)
  [void]$list.Columns.Add("Pause", 70)
  [void]$list.Columns.Add("Chemin", 450)

  $serviceList = New-Object System.Windows.Forms.ListView
  $serviceList.Dock = "Fill"
  $serviceList.View = "Details"
  $serviceList.CheckBoxes = $true
  $serviceList.FullRowSelect = $true
  $serviceList.GridLines = $false
  $serviceList.HideSelection = $false
  $serviceList.ShowItemToolTips = $true
  [void]$serviceList.Columns.Add("Action", 100)
  [void]$serviceList.Columns.Add("Prudence", 90)
  [void]$serviceList.Columns.Add("Nom affiche", 260)
  [void]$serviceList.Columns.Add("Nom service", 220)

  $processList = New-Object System.Windows.Forms.ListView
  $processList.Dock = "Fill"
  $processList.View = "Details"
  $processList.CheckBoxes = $true
  $processList.FullRowSelect = $true
  $processList.GridLines = $false
  $processList.HideSelection = $false
  $processList.ShowItemToolTips = $true
  [void]$processList.Columns.Add("Action", 100)
  [void]$processList.Columns.Add("Prudence", 90)
  [void]$processList.Columns.Add("Nom affiche", 260)
  [void]$processList.Columns.Add("Processus", 220)
  [void]$processList.Columns.Add("Chemin", 330)

  $networkList = New-Object System.Windows.Forms.ListView
  $networkList.Dock = "Fill"
  $networkList.View = "Details"
  $networkList.CheckBoxes = $true
  $networkList.FullRowSelect = $true
  $networkList.GridLines = $false
  $networkList.HideSelection = $false
  $networkList.ShowItemToolTips = $true
  [void]$networkList.Columns.Add("Action", 100)
  [void]$networkList.Columns.Add("Prudence", 90)
  [void]$networkList.Columns.Add("Conserver", 90)
  [void]$networkList.Columns.Add("Nom", 180)
  [void]$networkList.Columns.Add("Description", 260)

  [void]$appsTab.Controls.Add($list)
  [void]$servicesTab.Controls.Add($serviceList)
  [void]$processesTab.Controls.Add($processList)
  [void]$networkTab.Controls.Add($networkList)

  $securityPanel = New-Object System.Windows.Forms.TableLayoutPanel
  $securityPanel.Dock = "Fill"
  $securityPanel.RowCount = 5
  $securityPanel.ColumnCount = 1
  $securityPanel.Padding = New-Object System.Windows.Forms.Padding(14)
  [void]$securityPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 68)))
  [void]$securityPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$securityPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$securityPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 34)))
  [void]$securityPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

  $securityWarningLabel = New-Object System.Windows.Forms.Label
  $securityWarningLabel.Dock = "Fill"
  $securityWarningLabel.Text = "Options sensibles. A utiliser seulement si tu sais que ta session audio est hors ligne ou maitrisee. L'etat precedent est sauvegarde et restaure par le bouton Restaurer."
  $securityWarningLabel.TextAlign = "MiddleLeft"

  $disableFirewallCheckBox = New-Object System.Windows.Forms.CheckBox
  $disableFirewallCheckBox.Text = "Couper temporairement le pare-feu Windows"
  $disableFirewallCheckBox.Dock = "Fill"
  $disableFirewallCheckBox.TextAlign = "MiddleLeft"
  $rowToolTip.SetToolTip($disableFirewallCheckBox, "Coupe temporairement les profils de pare-feu Windows pendant la session audio.`nL'etat precedent est memorise puis restaure par Restaurer.")

  $disableDefenderRealtimeCheckBox = New-Object System.Windows.Forms.CheckBox
  $disableDefenderRealtimeCheckBox.Text = "Couper temporairement le scan temps reel Microsoft Defender"
  $disableDefenderRealtimeCheckBox.Dock = "Fill"
  $disableDefenderRealtimeCheckBox.TextAlign = "MiddleLeft"
  $rowToolTip.SetToolTip($disableDefenderRealtimeCheckBox, "Demande a Microsoft Defender de suspendre le scan temps reel pendant la session.`nWindows peut refuser selon les protections actives.")

  $disableDefenderTasksCheckBox = New-Object System.Windows.Forms.CheckBox
  $disableDefenderTasksCheckBox.Text = "Suspendre temporairement les taches planifiees Microsoft Defender"
  $disableDefenderTasksCheckBox.Dock = "Fill"
  $disableDefenderTasksCheckBox.TextAlign = "MiddleLeft"
  $rowToolTip.SetToolTip($disableDefenderTasksCheckBox, "Suspend les taches planifiees Defender detectees avant la session.`nElles sont remises dans leur etat initial a la restauration.")

  $securityInfoTextBox = New-Object System.Windows.Forms.TextBox
  $securityInfoTextBox.Dock = "Fill"
  $securityInfoTextBox.Multiline = $true
  $securityInfoTextBox.ReadOnly = $true
  $securityInfoTextBox.ScrollBars = "Vertical"
  $securityInfoTextBox.Text = "Ces options ne sont jamais cochees par defaut.`r`nLa simulation les liste sans les appliquer.`r`nAu lancement reel, une confirmation explicite est demandee.`r`nLa restauration remet les profils de pare-feu, le scan temps reel Defender et les taches Defender detectes avant la session.`r`nLe service Defender lui-meme est protege par Windows : si Windows bloque une action, le journal l'indique et l'outil continue sans pretendre que l'action a reussi."

  [void]$securityPanel.Controls.Add($securityWarningLabel, 0, 0)
  [void]$securityPanel.Controls.Add($disableFirewallCheckBox, 0, 1)
  [void]$securityPanel.Controls.Add($disableDefenderRealtimeCheckBox, 0, 2)
  [void]$securityPanel.Controls.Add($disableDefenderTasksCheckBox, 0, 3)
  [void]$securityPanel.Controls.Add($securityInfoTextBox, 0, 4)
  [void]$securityTab.Controls.Add($securityPanel)

  $diagnosticPanel = New-Object System.Windows.Forms.TableLayoutPanel
  $diagnosticPanel.Dock = "Fill"
  $diagnosticPanel.RowCount = 2
  $diagnosticPanel.ColumnCount = 1
  [void]$diagnosticPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 42)))
  [void]$diagnosticPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

  $diagnosticButtonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
  $diagnosticButtonPanel.Dock = "Fill"
  $diagnosticButtonPanel.FlowDirection = "LeftToRight"

  $refreshDiagnosticButton = New-Object System.Windows.Forms.Button
  $refreshDiagnosticButton.Text = "Actualiser"
  $refreshDiagnosticButton.Width = 90

  $exportDiagnosticButton = New-Object System.Windows.Forms.Button
  $exportDiagnosticButton.Text = "Exporter log"
  $exportDiagnosticButton.Width = 100

  [void]$diagnosticButtonPanel.Controls.Add($refreshDiagnosticButton)
  [void]$diagnosticButtonPanel.Controls.Add($exportDiagnosticButton)

  $diagnosticTextBox = New-Object System.Windows.Forms.TextBox
  $diagnosticTextBox.Dock = "Fill"
  $diagnosticTextBox.Multiline = $true
  $diagnosticTextBox.ReadOnly = $true
  $diagnosticTextBox.ScrollBars = "Both"
  $diagnosticTextBox.WordWrap = $false
  $diagnosticTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)

  [void]$diagnosticPanel.Controls.Add($diagnosticButtonPanel, 0, 0)
  [void]$diagnosticPanel.Controls.Add($diagnosticTextBox, 0, 1)
  [void]$diagnosticTab.Controls.Add($diagnosticPanel)

  [void]$tabControl.TabPages.Add($appsTab)
  [void]$tabControl.TabPages.Add($servicesTab)
  [void]$tabControl.TabPages.Add($processesTab)
  [void]$tabControl.TabPages.Add($networkTab)
  [void]$tabControl.TabPages.Add($securityTab)
  [void]$tabControl.TabPages.Add($diagnosticTab)

  $bottomPanel = New-Object System.Windows.Forms.TableLayoutPanel
  $bottomPanel.Dock = "Bottom"
  $bottomPanel.Height = 54
  $bottomPanel.ColumnCount = 2
  $bottomPanel.RowCount = 1
  $bottomPanel.Padding = New-Object System.Windows.Forms.Padding(8)
  [void]$bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 140)))
  [void]$bottomPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

  $signatureLabel = New-Object System.Windows.Forms.Label
  $signatureLabel.Text = "By Mamat"
  $signatureLabel.Dock = "Fill"
  $signatureLabel.TextAlign = "MiddleCenter"
  $signatureLabel.ForeColor = [System.Drawing.Color]::Black
  $signatureLabel.Font = New-Object System.Drawing.Font($form.Font.FontFamily, 9, [System.Drawing.FontStyle]::Italic)

  $buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
  $buttonPanel.Dock = "Fill"
  $buttonPanel.FlowDirection = "RightToLeft"
  $buttonPanel.WrapContents = $false

  $buttonSignatureLabel = New-Object System.Windows.Forms.Label
  $buttonSignatureLabel.Text = "By Mamat"
  $buttonSignatureLabel.Width = 85
  $buttonSignatureLabel.Height = 30
  $buttonSignatureLabel.TextAlign = "MiddleLeft"
  $buttonSignatureLabel.ForeColor = [System.Drawing.Color]::Black
  $buttonSignatureLabel.Font = New-Object System.Drawing.Font($form.Font.FontFamily, 8, [System.Drawing.FontStyle]::Italic)

  [void]$bottomPanel.Controls.Add($signatureLabel, 0, 0)
  [void]$bottomPanel.Controls.Add($buttonPanel, 1, 0)

  $launchButton = New-Object System.Windows.Forms.Button
  $launchButton.Text = "Lancer"
  $launchButton.Width = 105
  $launchButton.Height = 30

  $cancelButton = New-Object System.Windows.Forms.Button
  $cancelButton.Text = "Annuler"
  $cancelButton.Width = 95
  $cancelButton.Height = 30

  $restoreButton = New-Object System.Windows.Forms.Button
  $restoreButton.Text = "Restaurer"
  $restoreButton.Width = 105
  $restoreButton.Height = 30

  $openConfigButton = New-Object System.Windows.Forms.Button
  $openConfigButton.Text = "Liste"
  $openConfigButton.Width = 85
  $openConfigButton.Height = 30

  $addButton = New-Object System.Windows.Forms.Button
  $addButton.Text = "Ajouter"
  $addButton.Width = 90
  $addButton.Height = 30

  $removeButton = New-Object System.Windows.Forms.Button
  $removeButton.Text = "Supprimer"
  $removeButton.Width = 100
  $removeButton.Height = 30

  $toggleNetworkKeepButton = New-Object System.Windows.Forms.Button
  $toggleNetworkKeepButton.Text = "Carte audio"
  $toggleNetworkKeepButton.Width = 95
  $toggleNetworkKeepButton.Height = 30
  $toggleNetworkKeepButton.AccessibleDescription = "Choisit les cartes reseau audio a conserver. Une carte protegee ne sera pas desactivee pendant la session audio, meme si elle est cochee."
  $rowToolTip.SetToolTip($toggleNetworkKeepButton, "Carte audio : choisit les cartes reseau a proteger.`nA utiliser pour Dante, DVS, console, controle ou reseau audio.`nSans ligne selectionnee, ouvre la liste des cartes Windows detectees.")

  $selectAllButton = New-Object System.Windows.Forms.Button
  $selectAllButton.Text = "Tout"
  $selectAllButton.Width = 75
  $selectAllButton.Height = 30

  $selectNoneButton = New-Object System.Windows.Forms.Button
  $selectNoneButton.Text = "Aucun"
  $selectNoneButton.Width = 75
  $selectNoneButton.Height = 30

  $rememberCheckBox = New-Object System.Windows.Forms.CheckBox
  $rememberCheckBox.Text = "Memoriser"
  $rememberCheckBox.Checked = $true
  $rememberCheckBox.Width = 100
  $rememberCheckBox.Height = 30
  $rememberCheckBox.TextAlign = "MiddleLeft"

  $simulationCheckBox = New-Object System.Windows.Forms.CheckBox
  $simulationCheckBox.Text = "Simulation"
  $simulationCheckBox.Checked = $false
  $simulationCheckBox.Width = 100
  $simulationCheckBox.Height = 30
  $simulationCheckBox.TextAlign = "MiddleLeft"

  foreach ($control in @(
    $launchButton,
    $cancelButton,
    $restoreButton,
    $openConfigButton,
    $addButton,
    $removeButton,
    $toggleNetworkKeepButton,
    $selectAllButton,
    $selectNoneButton,
    $simulationCheckBox,
    $rememberCheckBox,
    $buttonSignatureLabel
  )) {
    [void]$buttonPanel.Controls.Add($control)
  }

  function Load-PowerPlanList {
    $powerPlanComboBox.Items.Clear()

    $plans = @(Get-PowerPlans)
    $plan = Get-Prop -InputObject $Config -Name "audioPlan" -Default $null
    $configuredName = [string](Get-Prop -InputObject $plan -Name "name" -Default "Mode Audio")
    $configuredGuid = [string](Get-Prop -InputObject $plan -Name "expectedGuid" -Default "")
    $selectedIndex = -1
    $index = 0

    foreach ($powerPlan in $plans) {
      [void]$powerPlanComboBox.Items.Add($powerPlan)
      if (($configuredGuid -and $powerPlan.guid -eq $configuredGuid) -or ($powerPlan.name -eq $configuredName)) {
        $selectedIndex = $index
      }
      $index++
    }

    if ($selectedIndex -lt 0 -and $powerPlanComboBox.Items.Count -gt 0) {
      $selectedIndex = 0
    }

    if ($selectedIndex -ge 0) {
      $powerPlanComboBox.SelectedIndex = $selectedIndex
    }
  }

  function Save-SelectedPowerPlan {
    if ($null -eq $powerPlanComboBox.SelectedItem) { return }

    $selectedPlan = $powerPlanComboBox.SelectedItem
    $plan = Get-Prop -InputObject $Config -Name "audioPlan" -Default $null
    if ($null -eq $plan) {
      $plan = [pscustomobject][ordered]@{
        name = "Mode Audio"
        expectedGuid = ""
        powFile = "Mode_Audio.pow"
      }
      Set-Prop -InputObject $Config -Name "audioPlan" -Value $plan
    }

    Set-Prop -InputObject $plan -Name "name" -Value ([string]$selectedPlan.name)
    Set-Prop -InputObject $plan -Name "expectedGuid" -Value ([string]$selectedPlan.guid)
  }

  function Load-ProfileList {
    $profileComboBox.Items.Clear()
    $profiles = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))
    $activeProfile = [string](Get-Prop -InputObject $Config -Name "activeProfile" -Default "Defaut")
    $selectedIndex = -1
    $index = 0

    foreach ($profile in $profiles) {
      [void]$profileComboBox.Items.Add($profile)
      if ([string](Get-Prop -InputObject $profile -Name "name" -Default "") -eq $activeProfile) {
        $selectedIndex = $index
      }
      $index++
    }

    if ($selectedIndex -lt 0 -and $profileComboBox.Items.Count -gt 0) { $selectedIndex = 0 }
    if ($selectedIndex -ge 0) { $profileComboBox.SelectedIndex = $selectedIndex }
  }

  function Set-EnabledByNames {
    param(
      [Parameter(Mandatory=$true)][string]$PropertyName,
      [AllowEmptyCollection()][object[]]$Names = @()
    )

    $safeNames = @($Names)
    foreach ($entry in (ConvertTo-Array (Get-Prop -InputObject $Config -Name $PropertyName -Default @()))) {
      $entryName = [string](Get-Prop -InputObject $entry -Name "name" -Default "")
      Set-Prop -InputObject $entry -Name "enabled" -Value ($entryName -in $safeNames)
    }
  }

  function Apply-SelectedProfile {
    if ($null -eq $profileComboBox.SelectedItem) { return }

    $profile = $profileComboBox.SelectedItem
    $profileName = [string](Get-Prop -InputObject $profile -Name "name" -Default "Defaut")
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $profileName

    $apps = @(ConvertTo-Array (Get-Prop -InputObject $profile -Name "apps" -Default @()))
    $services = @(ConvertTo-Array (Get-Prop -InputObject $profile -Name "services" -Default @()))
    $processes = @(ConvertTo-Array (Get-Prop -InputObject $profile -Name "processes" -Default @()))
    $adapters = @(ConvertTo-Array (Get-Prop -InputObject $profile -Name "networkAdapters" -Default @()))

    Set-EnabledByNames -PropertyName "apps" -Names $apps
    Set-EnabledByNames -PropertyName "services" -Names $services
    Set-EnabledByNames -PropertyName "processes" -Names $processes
    Set-EnabledByNames -PropertyName "networkAdapters" -Names $adapters

    $profilePlanName = [string](Get-Prop -InputObject $profile -Name "audioPlanName" -Default "")
    $profilePlanGuid = [string](Get-Prop -InputObject $profile -Name "audioPlanGuid" -Default "")
    $plan = Get-Prop -InputObject $Config -Name "audioPlan" -Default $null
    if ($plan -and (-not [string]::IsNullOrWhiteSpace($profilePlanName))) {
      Set-Prop -InputObject $plan -Name "name" -Value $profilePlanName
      Set-Prop -InputObject $plan -Name "expectedGuid" -Value $profilePlanGuid
      Load-PowerPlanList
    }

    Load-AppList
    Load-ServiceList
    Load-ProcessList
    Load-NetworkList
  }

  function Get-CheckedNamesFromList {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$TargetList)
    $names = @()
    foreach ($item in $TargetList.Items) {
      if ($item.Checked) {
        $names += [string](Get-Prop -InputObject $item.Tag -Name "name" -Default "")
      }
    }
    return $names
  }

  function Get-ProfileByName {
    param([Parameter(Mandatory=$true)][string]$ProfileName)

    foreach ($profile in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))) {
      if ([string](Get-Prop -InputObject $profile -Name "name" -Default "") -eq $ProfileName) {
        return $profile
      }
    }

    return $null
  }

  function Test-ProfileNameAvailable {
    param(
      [Parameter(Mandatory=$true)][string]$ProfileName,
      [string]$AllowedExistingName = ""
    )

    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
      [System.Windows.Forms.MessageBox]::Show($form, "Le nom du profil ne peut pas etre vide.", "Session Audio", "OK", "Warning") | Out-Null
      return $false
    }

    foreach ($profile in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))) {
      $name = [string](Get-Prop -InputObject $profile -Name "name" -Default "")
      if ($name -eq $ProfileName -and $name -ne $AllowedExistingName) {
        [System.Windows.Forms.MessageBox]::Show($form, "Ce nom de profil existe deja.", "Session Audio", "OK", "Warning") | Out-Null
        return $false
      }
    }

    return $true
  }

  function New-ProfileFromCurrentSelection {
    param([Parameter(Mandatory=$true)][string]$ProfileName)

    Save-SelectedPowerPlan
    Save-SelectedServices
    Save-SelectedProcesses
    Save-SelectedNetworkAdapters
    Save-SecurityOptions
    foreach ($item in $list.Items) {
      Set-Prop -InputObject $item.Tag -Name "enabled" -Value ([bool]$item.Checked)
    }

    $plan = Get-Prop -InputObject $Config -Name "audioPlan" -Default $null
    return [pscustomobject][ordered]@{
      name = $ProfileName
      audioPlanName = [string](Get-Prop -InputObject $plan -Name "name" -Default "")
      audioPlanGuid = [string](Get-Prop -InputObject $plan -Name "expectedGuid" -Default "")
      apps = @(Get-CheckedNamesFromList -TargetList $list)
      services = @(Get-CheckedNamesFromList -TargetList $serviceList)
      processes = @(Get-CheckedNamesFromList -TargetList $processList)
      networkAdapters = @(Get-CheckedNamesFromList -TargetList $networkList)
    }
  }

  function Save-CurrentSelectionAsProfile {
    Add-Type -AssemblyName Microsoft.VisualBasic

    $currentName = if ($profileComboBox.SelectedItem) {
      [string](Get-Prop -InputObject $profileComboBox.SelectedItem -Name "name" -Default "Defaut")
    } else {
      "Defaut"
    }

    $profileName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du profil", "Sauver profil", $currentName)
    if ([string]::IsNullOrWhiteSpace($profileName)) { return }
    if (-not (Test-ProfileNameAvailable -ProfileName $profileName -AllowedExistingName $currentName)) { return }

    $profile = New-ProfileFromCurrentSelection -ProfileName $profileName

    $profiles = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))
    $newProfiles = @()
    $replaced = $false
    foreach ($existingProfile in $profiles) {
      if ([string](Get-Prop -InputObject $existingProfile -Name "name" -Default "") -eq $profileName) {
        $newProfiles += $profile
        $replaced = $true
      } else {
        $newProfiles += $existingProfile
      }
    }
    if (-not $replaced) { $newProfiles += $profile }

    Set-Prop -InputObject $Config -Name "profiles" -Value $newProfiles
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $profileName
    Save-Config -Config $Config
    Load-ProfileList
  }

  function Rename-SelectedProfile {
    Add-Type -AssemblyName Microsoft.VisualBasic
    if ($null -eq $profileComboBox.SelectedItem) { return }

    $oldName = [string](Get-Prop -InputObject $profileComboBox.SelectedItem -Name "name" -Default "")
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nouveau nom du profil", "Renommer profil", $oldName)
    if (-not (Test-ProfileNameAvailable -ProfileName $newName -AllowedExistingName $oldName)) { return }

    Set-Prop -InputObject $profileComboBox.SelectedItem -Name "name" -Value $newName
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $newName
    Save-Config -Config $Config
    Load-ProfileList
  }

  function Duplicate-SelectedProfile {
    Add-Type -AssemblyName Microsoft.VisualBasic
    if ($null -eq $profileComboBox.SelectedItem) { return }

    $oldName = [string](Get-Prop -InputObject $profileComboBox.SelectedItem -Name "name" -Default "Profil")
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du nouveau profil", "Dupliquer profil", "$oldName copie")
    if (-not (Test-ProfileNameAvailable -ProfileName $newName)) { return }

    $sourceJson = $profileComboBox.SelectedItem | ConvertTo-Json -Depth 8
    $newProfile = $sourceJson | ConvertFrom-Json
    Set-Prop -InputObject $newProfile -Name "name" -Value $newName

    $profiles = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))
    $profiles += $newProfile
    Set-Prop -InputObject $Config -Name "profiles" -Value $profiles
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $newName
    Save-Config -Config $Config
    Load-ProfileList
  }

  function Delete-SelectedProfile {
    if ($null -eq $profileComboBox.SelectedItem) { return }

    $profiles = @(ConvertTo-Array (Get-Prop -InputObject $Config -Name "profiles" -Default @()))
    if ($profiles.Count -le 1) {
      [System.Windows.Forms.MessageBox]::Show($form, "Impossible de supprimer le dernier profil.", "Session Audio", "OK", "Warning") | Out-Null
      return
    }

    $profileName = [string](Get-Prop -InputObject $profileComboBox.SelectedItem -Name "name" -Default "")
    $confirm = [System.Windows.Forms.MessageBox]::Show(
      $form,
      "Supprimer le profil '$profileName' ?",
      "Session Audio",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $remainingProfiles = @()
    foreach ($profile in $profiles) {
      if ([string](Get-Prop -InputObject $profile -Name "name" -Default "") -ne $profileName) {
        $remainingProfiles += $profile
      }
    }

    $newActiveProfile = [string](Get-Prop -InputObject $remainingProfiles[0] -Name "name" -Default "")
    Set-Prop -InputObject $Config -Name "profiles" -Value $remainingProfiles
    Set-Prop -InputObject $Config -Name "activeProfile" -Value $newActiveProfile
    Save-Config -Config $Config
    Load-ProfileList
  }

  function Load-AppList {
    $list.Items.Clear()
    foreach ($app in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "apps" -Default @()))) {
      $category = [string](Get-Prop -InputObject $app -Name "category" -Default "Divers")
      $name = [string](Get-Prop -InputObject $app -Name "name" -Default "")
      $path = [string](Get-Prop -InputObject $app -Name "path" -Default "")
      $delay = Get-AppDelaySeconds -App $app
      $risk = Get-EntryRisk -Kind "app" -Entry $app

      $item = New-Object System.Windows.Forms.ListViewItem($category)
      [void]$item.SubItems.Add($name)
      [void]$item.SubItems.Add($risk)
      [void]$item.SubItems.Add(("{0}s" -f $delay))
      [void]$item.SubItems.Add($path)
      $item.Checked = Test-EntryEnabled -Entry $app -Default $false
      $item.Tag = $app
      $item.ToolTipText = Get-EntryTooltipText -Kind "app" -Entry $app
      [void]$list.Items.Add($item)
    }
  }

  function Load-ServiceList {
    $serviceList.Items.Clear()
    foreach ($serviceConfig in (Get-ManagedServiceConfigs -Config $Config)) {
      $action = [string](Get-Prop -InputObject $serviceConfig -Name "action" -Default "Stop")
      $actionLabel = if ($action.ToLowerInvariant() -eq "start") { "Demarrer" } else { "Arreter" }
      $displayName = [string](Get-Prop -InputObject $serviceConfig -Name "displayName" -Default "")
      $name = [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default "")
      if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $name }
      $risk = Get-EntryRisk -Kind "service" -Entry $serviceConfig

      $item = New-Object System.Windows.Forms.ListViewItem($actionLabel)
      [void]$item.SubItems.Add($risk)
      [void]$item.SubItems.Add($displayName)
      [void]$item.SubItems.Add($name)
      $item.Checked = Test-EntryEnabled -Entry $serviceConfig -Default $true
      $item.Tag = $serviceConfig
      $item.ToolTipText = Get-EntryTooltipText -Kind "service" -Entry $serviceConfig
      [void]$serviceList.Items.Add($item)
    }
  }

  function Save-SelectedServices {
    foreach ($item in $serviceList.Items) {
      Set-Prop -InputObject $item.Tag -Name "enabled" -Value ([bool]$item.Checked)
    }
  }

  function Load-ProcessList {
    $processList.Items.Clear()
    foreach ($processConfig in (Get-ManagedProcessConfigs -Config $Config)) {
      $name = [string](Get-Prop -InputObject $processConfig -Name "name" -Default "")
      $displayName = [string](Get-Prop -InputObject $processConfig -Name "displayName" -Default $name)
      $path = [string](Get-Prop -InputObject $processConfig -Name "path" -Default "")
      $risk = Get-EntryRisk -Kind "process" -Entry $processConfig

      $item = New-Object System.Windows.Forms.ListViewItem("Fermer")
      [void]$item.SubItems.Add($risk)
      [void]$item.SubItems.Add($displayName)
      [void]$item.SubItems.Add($name)
      [void]$item.SubItems.Add($path)
      $item.Checked = Test-EntryEnabled -Entry $processConfig -Default $false
      $item.Tag = $processConfig
      $item.ToolTipText = Get-EntryTooltipText -Kind "process" -Entry $processConfig
      [void]$processList.Items.Add($item)
    }
  }

  function Save-SelectedProcesses {
    foreach ($item in $processList.Items) {
      Set-Prop -InputObject $item.Tag -Name "enabled" -Value ([bool]$item.Checked)
    }
  }

  function Load-NetworkList {
    $networkList.Items.Clear()
    foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
      $action = [string](Get-Prop -InputObject $adapterConfig -Name "action" -Default "Disable")
      $actionLabel = if ($action.ToLowerInvariant() -eq "enable") { "Activer" } else { "Desactiver" }
      $name = [string](Get-Prop -InputObject $adapterConfig -Name "name" -Default "")
      $displayName = [string](Get-Prop -InputObject $adapterConfig -Name "displayName" -Default $name)
      $risk = Get-EntryRisk -Kind "network" -Entry $adapterConfig
      $keepLabel = if (Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $adapterConfig -Name "audioKeep" -Default $false) }) -Default $false) { "Oui" } else { "Non" }

      $item = New-Object System.Windows.Forms.ListViewItem($actionLabel)
      [void]$item.SubItems.Add($risk)
      [void]$item.SubItems.Add($keepLabel)
      [void]$item.SubItems.Add($name)
      [void]$item.SubItems.Add($displayName)
      $item.Checked = Test-EntryEnabled -Entry $adapterConfig -Default $false
      $item.Tag = $adapterConfig
      $item.ToolTipText = Get-EntryTooltipText -Kind "network" -Entry $adapterConfig
      [void]$networkList.Items.Add($item)
    }
  }

  function Save-SelectedNetworkAdapters {
    foreach ($item in $networkList.Items) {
      Set-Prop -InputObject $item.Tag -Name "enabled" -Value ([bool]$item.Checked)
    }
  }

  function Load-SecurityOptions {
    $securityConfig = Get-WindowsSecurityConfig -Config $Config
    $disableFirewallCheckBox.Checked = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $securityConfig -Name "disableFirewall" -Default $false) }) -Default $false
    $disableDefenderRealtimeCheckBox.Checked = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $securityConfig -Name "disableDefenderRealtime" -Default $false) }) -Default $false
    $disableDefenderTasksCheckBox.Checked = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $securityConfig -Name "disableDefenderScheduledTasks" -Default $false) }) -Default $false
  }

  function Save-SecurityOptions {
    $securityConfig = Get-WindowsSecurityConfig -Config $Config
    Set-Prop -InputObject $securityConfig -Name "disableFirewall" -Value ([bool]$disableFirewallCheckBox.Checked)
    Set-Prop -InputObject $securityConfig -Name "disableDefenderRealtime" -Value ([bool]$disableDefenderRealtimeCheckBox.Checked)
    Set-Prop -InputObject $securityConfig -Name "disableDefenderScheduledTasks" -Value ([bool]$disableDefenderTasksCheckBox.Checked)
    Set-Prop -InputObject $securityConfig -Name "requireConfirmation" -Value $true
    Set-Prop -InputObject $Config -Name "windowsSecurity" -Value $securityConfig
  }

  function Confirm-SensitiveSecurityOptions {
    if (-not $disableFirewallCheckBox.Checked -and -not $disableDefenderRealtimeCheckBox.Checked -and -not $disableDefenderTasksCheckBox.Checked) { return $true }

    $message = "Tu as coche une option de securite sensible.`n`n"
    if ($disableFirewallCheckBox.Checked) {
      $message += "- Le pare-feu Windows sera coupe temporairement.`n"
    }
    if ($disableDefenderRealtimeCheckBox.Checked) {
      $message += "- Le scan temps reel Microsoft Defender sera coupe temporairement.`n"
    }
    if ($disableDefenderTasksCheckBox.Checked) {
      $message += "- Les taches planifiees Microsoft Defender seront suspendues temporairement.`n"
    }
    $message += "`nL'etat precedent sera sauvegarde et le bouton Restaurer devra etre utilise pour revenir au mode bureau normal.`n`nContinuer ?"

    $result = [System.Windows.Forms.MessageBox]::Show(
      $form,
      $message,
      "Confirmation securite",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    return ($result -eq [System.Windows.Forms.DialogResult]::Yes)
  }

  function Show-AudioKeepSelectionDialog {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Choisir les cartes audio"
    $dialog.StartPosition = "CenterParent"
    $dialog.Width = 620
    $dialog.Height = 430
    $dialog.MinimizeBox = $false
    $dialog.MaximizeBox = $false
    $dialog.FormBorderStyle = "FixedDialog"

    $dialogLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $dialogLayout.Dock = "Fill"
    $dialogLayout.RowCount = 3
    $dialogLayout.ColumnCount = 1
    $dialogLayout.Padding = New-Object System.Windows.Forms.Padding(10)
    [void]$dialogLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 54)))
    [void]$dialogLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$dialogLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 44)))

    $helpLabel = New-Object System.Windows.Forms.Label
    $helpLabel.Dock = "Fill"
    $helpLabel.Text = "Coche les cartes reseau a conserver pour l'audio. Elles ne seront pas desactivees pendant la session, meme si elles sont dans la liste reseau."
    $helpLabel.TextAlign = "MiddleLeft"

    $adapterCheckList = New-Object System.Windows.Forms.CheckedListBox
    $adapterCheckList.Dock = "Fill"
    $adapterCheckList.CheckOnClick = $true
    $adapterCheckList.HorizontalScrollbar = $true
    $adapterCheckList.DisplayMember = "Label"

    $managedAdapterConfigs = @(Get-ManagedNetworkAdapterConfigs -Config $Config)
    $knownAdapterNames = @{}

    foreach ($adapterConfig in $managedAdapterConfigs) {
      $name = [string](Get-Prop -InputObject $adapterConfig -Name "name" -Default "")
      $displayName = [string](Get-Prop -InputObject $adapterConfig -Name "displayName" -Default $name)
      if (-not [string]::IsNullOrWhiteSpace($name)) {
        $knownAdapterNames[$name.ToLowerInvariant()] = $true
      }
      $label = if ([string]::IsNullOrWhiteSpace($displayName) -or $displayName -eq $name) { $name } else { "$displayName - $name" }
      $checked = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $adapterConfig -Name "audioKeep" -Default $false) }) -Default $false
      $index = $adapterCheckList.Items.Add([pscustomobject]@{ Label = $label; Config = $adapterConfig; Name = $name; DisplayName = $displayName; DetectedOnly = $false })
      $adapterCheckList.SetItemChecked($index, $checked)
    }

    try {
      foreach ($windowsAdapter in @(Get-NetAdapter | Sort-Object Name)) {
        $adapterName = [string]$windowsAdapter.Name
        if ([string]::IsNullOrWhiteSpace($adapterName)) { continue }
        if ($knownAdapterNames.ContainsKey($adapterName.ToLowerInvariant())) { continue }

        $adapterDescription = [string]$windowsAdapter.InterfaceDescription
        $adapterStatus = [string]$windowsAdapter.Status
        $adapterSpeed = [string]$windowsAdapter.LinkSpeed
        $label = "$adapterName - $adapterDescription ($adapterStatus, $adapterSpeed)"
        [void]$adapterCheckList.Items.Add([pscustomobject]@{
          Label = $label
          Config = $null
          Name = $adapterName
          DisplayName = $adapterDescription
          DetectedOnly = $true
        })
      }
    } catch {
      [void]$adapterCheckList.Items.Add([pscustomobject]@{
        Label = "Impossible de lister les cartes Windows : $($_.Exception.Message)"
        Config = $null
        Name = ""
        DisplayName = ""
        DetectedOnly = $true
      })
    }

    $buttonRow = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttonRow.Dock = "Fill"
    $buttonRow.FlowDirection = "RightToLeft"

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Valider"
    $okButton.Width = 95
    $okButton.Height = 30
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelDialogButton = New-Object System.Windows.Forms.Button
    $cancelDialogButton.Text = "Annuler"
    $cancelDialogButton.Width = 95
    $cancelDialogButton.Height = 30
    $cancelDialogButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    [void]$buttonRow.Controls.Add($okButton)
    [void]$buttonRow.Controls.Add($cancelDialogButton)
    [void]$dialogLayout.Controls.Add($helpLabel, 0, 0)
    [void]$dialogLayout.Controls.Add($adapterCheckList, 0, 1)
    [void]$dialogLayout.Controls.Add($buttonRow, 0, 2)
    [void]$dialog.Controls.Add($dialogLayout)
    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelDialogButton

    $result = $dialog.ShowDialog($form)
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) { return $false }

    $newAdapters = @()
    for ($i = 0; $i -lt $adapterCheckList.Items.Count; $i++) {
      $entry = $adapterCheckList.Items[$i]
      $isChecked = [bool]$adapterCheckList.GetItemChecked($i)

      if ($null -ne $entry.Config) {
        Set-Prop -InputObject $entry.Config -Name "audioKeep" -Value $isChecked
        continue
      }

      if ($isChecked -and -not [string]::IsNullOrWhiteSpace([string]$entry.Name)) {
        $newAdapters += [pscustomobject][ordered]@{
          name = [string]$entry.Name
          displayName = [string]$entry.DisplayName
          action = "Disable"
          enabled = $false
          audioKeep = $true
          description = "Carte reseau detectee dans Windows et marquee comme carte audio a conserver."
        }
      }
    }

    if ($newAdapters.Count -gt 0) {
      Set-Prop -InputObject $Config -Name "networkAdapters" -Value @($managedAdapterConfigs + $newAdapters)
    }

    Save-Config -Config $Config
    return $true
  }

  function Load-Diagnostic {
    $diagnosticTextBox.Lines = [string[]](Get-DiagnosticReportLines -Config $Config)
  }

  function Enable-ColumnSorting {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$TargetList)

    $TargetList.Tag = [pscustomobject]@{
      LastColumn = -1
      Ascending = $true
    }

    $TargetList.Add_ColumnClick({
      param($sender, $eventArgs)

      $state = $sender.Tag
      if ($state.LastColumn -eq $eventArgs.Column) {
        $state.Ascending = -not $state.Ascending
      } else {
        $state.LastColumn = $eventArgs.Column
        $state.Ascending = $true
      }

      $sender.ListViewItemSorter = [SessionAudioListViewItemComparer]::new($eventArgs.Column, [bool]$state.Ascending)
      $sender.Sort()
    })
  }

  function Enable-RowToolTips {
    param([Parameter(Mandatory=$true)][System.Windows.Forms.ListView]$TargetList)

    $TargetList.Add_MouseMove({
      param($sender, $eventArgs)

      $item = $sender.GetItemAt($eventArgs.X, $eventArgs.Y)
      if ($null -eq $item) {
        if ($script:lastToolTipKey -ne "") {
          $rowToolTip.Hide($sender)
          $script:lastToolTipKey = ""
        }
        return
      }

      $key = "$($sender.Handle)-$($item.Index)"
      if ($script:lastToolTipKey -eq $key) { return }

      $script:lastToolTipKey = $key
      $text = [string]$item.ToolTipText
      if ([string]::IsNullOrWhiteSpace($text)) { return }

      $rowToolTip.Show($text, $sender, $eventArgs.X + 18, $eventArgs.Y + 18, 12000)
    })

    $TargetList.Add_MouseLeave({
      param($sender, $eventArgs)
      $rowToolTip.Hide($sender)
      $script:lastToolTipKey = ""
    })
  }

  Load-PowerPlanList
  Load-AppList
  Load-ServiceList
  Load-ProcessList
  Load-NetworkList
  Load-SecurityOptions
  Load-ProfileList
  Load-Diagnostic

  Enable-ColumnSorting -TargetList $list
  Enable-ColumnSorting -TargetList $serviceList
  Enable-ColumnSorting -TargetList $processList
  Enable-ColumnSorting -TargetList $networkList
  Enable-RowToolTips -TargetList $list
  Enable-RowToolTips -TargetList $serviceList
  Enable-RowToolTips -TargetList $processList
  Enable-RowToolTips -TargetList $networkList

  $profileComboBox.Add_SelectedIndexChanged({
    Apply-SelectedProfile
  })

  $saveProfileButton.Add_Click({
    Save-CurrentSelectionAsProfile
  })

  $renameProfileButton.Add_Click({
    Rename-SelectedProfile
  })

  $duplicateProfileButton.Add_Click({
    Duplicate-SelectedProfile
  })

  $deleteProfileButton.Add_Click({
    Delete-SelectedProfile
  })

  $refreshDiagnosticButton.Add_Click({
    Load-Diagnostic
  })

  $exportDiagnosticButton.Add_Click({
    Write-DiagnosticReport -Config $Config
    [System.Windows.Forms.MessageBox]::Show($form, "Diagnostic exporte dans le log courant.", "Session Audio", "OK", "Information") | Out-Null
  })

  $launchButton.Add_Click({
    $selected = @()
    Save-SelectedPowerPlan

    foreach ($item in $list.Items) {
      if ($rememberCheckBox.Checked) {
        Set-Prop -InputObject $item.Tag -Name "enabled" -Value ([bool]$item.Checked)
      }
      if ($item.Checked) {
        $selected += $item.Tag
      }
    }
    Save-SelectedServices
    Save-SelectedProcesses
    Save-SelectedNetworkAdapters
    Save-SecurityOptions

    if ((-not $simulationCheckBox.Checked) -and (-not (Confirm-SensitiveSecurityOptions))) {
      return
    }

    if ($rememberCheckBox.Checked) {
      Save-Config -Config $Config
    }

    $form.Tag = [pscustomobject][ordered]@{
      action = if ($simulationCheckBox.Checked) { "Simulate" } else { "Launch" }
      apps = $selected
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
  })

  $restoreButton.Add_Click({
    $form.Tag = [pscustomobject][ordered]@{
      action = "Restore"
      apps = @()
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
  })

  $openConfigButton.Add_Click({
    Save-Config -Config $Config
    Open-ConfigFile
  })

  $addButton.Add_Click({
    if ($tabControl.SelectedTab -eq $servicesTab) {
      if (Add-ServiceFromDialog -Config $Config -Owner $form) {
        Load-ServiceList
      }
    } elseif ($tabControl.SelectedTab -eq $processesTab) {
      if (Add-ProcessFromDialog -Config $Config -Owner $form) {
        Load-ProcessList
      }
    } elseif ($tabControl.SelectedTab -eq $networkTab) {
      if (Add-NetworkAdapterFromDialog -Config $Config -Owner $form) {
        Load-NetworkList
      }
    } elseif ($tabControl.SelectedTab -eq $securityTab -or $tabControl.SelectedTab -eq $diagnosticTab) {
      return
    } else {
      if (Add-AppsFromDialog -Config $Config -Owner $form) {
        Load-AppList
      }
    }
  })

  $removeButton.Add_Click({
    $activeList = if ($tabControl.SelectedTab -eq $servicesTab) {
      $serviceList
    } elseif ($tabControl.SelectedTab -eq $processesTab) {
      $processList
    } elseif ($tabControl.SelectedTab -eq $networkTab) {
      $networkList
    } elseif ($tabControl.SelectedTab -eq $securityTab -or $tabControl.SelectedTab -eq $diagnosticTab) {
      return
    } else {
      $list
    }
    if ($activeList.SelectedItems.Count -eq 0) { return }

    $label = if ($activeList.SelectedItems.Count -eq 1) {
      [string]$activeList.SelectedItems[0].SubItems[1].Text
    } else {
      if ($tabControl.SelectedTab -eq $servicesTab) {
        "$($activeList.SelectedItems.Count) services"
      } elseif ($tabControl.SelectedTab -eq $processesTab) {
        "$($activeList.SelectedItems.Count) processus"
      } elseif ($tabControl.SelectedTab -eq $networkTab) {
        "$($activeList.SelectedItems.Count) adaptateurs"
      } else {
        "$($activeList.SelectedItems.Count) programmes"
      }
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
      $form,
      "Supprimer $label de la liste ?",
      "Session Audio",
      [System.Windows.Forms.MessageBoxButtons]::YesNo,
      [System.Windows.Forms.MessageBoxIcon]::Question
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $selectedTags = @()
    foreach ($item in $activeList.SelectedItems) {
      $selectedTags += $item.Tag
    }

    if ($tabControl.SelectedTab -eq $servicesTab) {
      $remainingServices = @()
      foreach ($serviceConfig in (Get-ManagedServiceConfigs -Config $Config)) {
        $remove = $false
        foreach ($tag in $selectedTags) {
          if ([object]::ReferenceEquals($serviceConfig, $tag)) {
            $remove = $true
            break
          }
        }

        if (-not $remove) {
          $remainingServices += $serviceConfig
        }
      }

      Set-Prop -InputObject $Config -Name "services" -Value $remainingServices
      Save-Config -Config $Config
      Load-ServiceList
    } elseif ($tabControl.SelectedTab -eq $processesTab) {
      $remainingProcesses = @()
      foreach ($processConfig in (Get-ManagedProcessConfigs -Config $Config)) {
        $remove = $false
        foreach ($tag in $selectedTags) {
          if ([object]::ReferenceEquals($processConfig, $tag)) {
            $remove = $true
            break
          }
        }

        if (-not $remove) {
          $remainingProcesses += $processConfig
        }
      }

      Set-Prop -InputObject $Config -Name "processes" -Value $remainingProcesses
      Save-Config -Config $Config
      Load-ProcessList
    } elseif ($tabControl.SelectedTab -eq $networkTab) {
      $remainingAdapters = @()
      foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
        $remove = $false
        foreach ($tag in $selectedTags) {
          if ([object]::ReferenceEquals($adapterConfig, $tag)) {
            $remove = $true
            break
          }
        }

        if (-not $remove) {
          $remainingAdapters += $adapterConfig
        }
      }

      Set-Prop -InputObject $Config -Name "networkAdapters" -Value $remainingAdapters
      Save-Config -Config $Config
      Load-NetworkList
    } else {
      $remainingApps = @()
      foreach ($app in (ConvertTo-Array (Get-Prop -InputObject $Config -Name "apps" -Default @()))) {
        $remove = $false
        foreach ($tag in $selectedTags) {
          if ([object]::ReferenceEquals($app, $tag)) {
            $remove = $true
            break
          }
        }

        if (-not $remove) {
          $remainingApps += $app
        }
      }

      Set-Prop -InputObject $Config -Name "apps" -Value $remainingApps
      Save-Config -Config $Config
      Load-AppList
    }
  })

  $toggleNetworkKeepButton.Add_Click({
    if ($tabControl.SelectedTab -ne $networkTab) {
      $tabControl.SelectedTab = $networkTab
    }

    if ($networkList.SelectedItems.Count -eq 0) {
      if (Show-AudioKeepSelectionDialog) {
        Load-NetworkList
      }
      return
    }

    foreach ($item in $networkList.SelectedItems) {
      $current = Test-EntryEnabled -Entry ([pscustomobject]@{ enabled = (Get-Prop -InputObject $item.Tag -Name "audioKeep" -Default $false) }) -Default $false
      Set-Prop -InputObject $item.Tag -Name "audioKeep" -Value (-not $current)
    }

    Save-Config -Config $Config
    Load-NetworkList
  })

  $refreshPlansButton.Add_Click({
    Load-PowerPlanList
  })

  $selectAllButton.Add_Click({
    $activeList = if ($tabControl.SelectedTab -eq $servicesTab) {
      $serviceList
    } elseif ($tabControl.SelectedTab -eq $processesTab) {
      $processList
    } elseif ($tabControl.SelectedTab -eq $networkTab) {
      $networkList
    } else {
      $list
    }
    foreach ($item in $activeList.Items) { $item.Checked = $true }
  })

  $selectNoneButton.Add_Click({
    $activeList = if ($tabControl.SelectedTab -eq $servicesTab) {
      $serviceList
    } elseif ($tabControl.SelectedTab -eq $processesTab) {
      $processList
    } elseif ($tabControl.SelectedTab -eq $networkTab) {
      $networkList
    } else {
      $list
    }
    foreach ($item in $activeList.Items) { $item.Checked = $false }
  })

  $cancelButton.Add_Click({
    $form.Tag = [pscustomobject][ordered]@{
      action = "Cancel"
      apps = @()
    }
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
  })

  $form.AcceptButton = $launchButton
  $form.CancelButton = $cancelButton
  [void]$form.Controls.Add($tabControl)
  [void]$form.Controls.Add($topPanel)
  [void]$form.Controls.Add($bottomPanel)
  [void]$form.ShowDialog()

  if ($form.Tag) { return $form.Tag }
  return [pscustomobject][ordered]@{
    action = "Cancel"
    apps = @()
  }
}

# Applique la configuration PC avant de lancer les logiciels selectionnes.
function Apply-AudioEnvironment {
  param([Parameter(Mandatory=$true)][object]$Config)

  if (-not (Test-IsAdmin)) {
    throw "Ce script doit etre lance en administrateur."
  }

  Save-EnvironmentState -Config $Config

  $schemeGuid = Ensure-AudioPowerPlan -Config $Config
  Enforce-CPUAndUSBSettings -SchemeGuid $schemeGuid

  foreach ($serviceConfig in (Get-ManagedServiceConfigs -Config $Config)) {
    if (Test-EntryEnabled -Entry $serviceConfig -Default $true) {
      Apply-ServiceAction -ServiceConfig $serviceConfig
    }
  }

  foreach ($processConfig in (Get-ManagedProcessConfigs -Config $Config)) {
    if (Test-EntryEnabled -Entry $processConfig -Default $false) {
      Close-ManagedProcess -ProcessConfig $processConfig
    }
  }

  foreach ($adapterConfig in (Get-ManagedNetworkAdapterConfigs -Config $Config)) {
    if (Test-EntryEnabled -Entry $adapterConfig -Default $false) {
      Apply-NetworkAdapterAction -AdapterConfig $adapterConfig
    }
  }

  Apply-WindowsSecuritySettings -Config $Config
}

function Start-SelectedApps {
  param([object[]]$Apps)

  foreach ($app in $Apps) {
    $appWasLaunched = Start-AppIfNotRunning -App $app
    if ($appWasLaunched) {
      $delaySeconds = Get-AppDelaySeconds -App $app
      if ($delaySeconds -gt 0) {
        $appName = [string](Get-Prop -InputObject $app -Name "name" -Default "application")
        Write-Log "Pause de $delaySeconds s apres $appName"
        Start-Sleep -Seconds $delaySeconds
      }
    }
  }
}

function Write-SessionPlanReport {
  param(
    [Parameter(Mandatory=$true)][string]$Mode,
    [object[]]$Apps = @()
  )

  Write-Log "=== RAPPORT SESSION AUDIO : $Mode ==="

  $plan = Get-Prop -InputObject $config -Name "audioPlan" -Default $null
  Write-Log ("Plan alimentation choisi : " + [string](Get-Prop -InputObject $plan -Name "name" -Default ""))

  $enabledServices = @(Get-ManagedServiceConfigs -Config $config | Where-Object { Test-EntryEnabled -Entry $_ -Default $true })
  $enabledProcesses = @(Get-ManagedProcessConfigs -Config $config | Where-Object { Test-EntryEnabled -Entry $_ -Default $false })
  $enabledAdapters = @(Get-ManagedNetworkAdapterConfigs -Config $config | Where-Object { Test-EntryEnabled -Entry $_ -Default $false })

  Write-Log ("Logiciels selectionnes : " + @($Apps).Count)
  foreach ($app in @($Apps)) {
    Write-Log ("  - Lancer : " + [string](Get-Prop -InputObject $app -Name "name" -Default ""))
  }

  Write-Log ("Services selectionnes : " + $enabledServices.Count)
  foreach ($serviceConfig in $enabledServices) {
    Write-Log ("  - " + [string](Get-Prop -InputObject $serviceConfig -Name "action" -Default "Stop") + " : " + [string](Get-Prop -InputObject $serviceConfig -Name "name" -Default ""))
  }

  Write-Log ("Processus selectionnes : " + $enabledProcesses.Count)
  foreach ($processConfig in $enabledProcesses) {
    Write-Log ("  - Fermer : " + [string](Get-Prop -InputObject $processConfig -Name "name" -Default ""))
  }

  Write-Log ("Adaptateurs reseau selectionnes : " + $enabledAdapters.Count)
  foreach ($adapterConfig in $enabledAdapters) {
    Write-Log ("  - " + [string](Get-Prop -InputObject $adapterConfig -Name "action" -Default "Disable") + " : " + [string](Get-Prop -InputObject $adapterConfig -Name "name" -Default ""))
  }

  Write-Log "Options securite Windows :"
  if (Test-WindowsSecurityOptionEnabled -Config $config -Name "disableFirewall") {
    Write-Log "  - Pare-feu Windows : couper temporairement"
  } else {
    Write-Log "  - Pare-feu Windows : aucune modification"
  }
  if (Test-WindowsSecurityOptionEnabled -Config $config -Name "disableDefenderRealtime") {
    Write-Log "  - Microsoft Defender : couper temporairement le scan temps reel"
  } else {
    Write-Log "  - Microsoft Defender scan temps reel : aucune modification"
  }
  if (Test-WindowsSecurityOptionEnabled -Config $config -Name "disableDefenderScheduledTasks") {
    Write-Log "  - Microsoft Defender : suspendre temporairement les taches planifiees"
  } else {
    Write-Log "  - Microsoft Defender taches planifiees : aucune modification"
  }

  Write-Log "=== FIN RAPPORT ==="
}

try {
  $config = Read-Config
  Initialize-Logging -Config $config

  if ($OpenConfig) {
    Open-ConfigFile
    return
  }

  Write-Log "=== SESSION AUDIO ==="

  if ($Restore) {
    Restore-Environment
    return
  }

  if ((-not $NoGui) -and (Confirm-PendingRestore)) {
    Restore-Environment
    return
  } elseif ((Test-Path -LiteralPath $StatePath) -and $NoGui) {
    Write-Log "ATTENTION : une session precedente n'a pas ete restauree : $StatePath"
  }

  if ($NoGui) {
    $selectedApps = Get-EnabledApps -Config $config
    $action = if ($Simulate) { "Simulate" } else { "Launch" }
  } else {
    $choice = Show-AppSelectionDialog -Config $config
    $action = [string](Get-Prop -InputObject $choice -Name "action" -Default "Cancel")

    if ($action -eq "Cancel") {
      Write-Log "Lancement annule"
      return
    }

    if ($action -eq "Restore") {
      Restore-Environment
      return
    }

    $selectedApps = @(ConvertTo-Array (Get-Prop -InputObject $choice -Name "apps" -Default @()))
  }

  if ($action -eq "Simulate") {
    Write-SessionPlanReport -Mode "SIMULATION" -Apps $selectedApps
    Write-Log "Simulation terminee : aucune modification appliquee."
    return
  }

  if ($NoGui -and ((Test-WindowsSecurityOptionEnabled -Config $config -Name "disableFirewall") -or (Test-WindowsSecurityOptionEnabled -Config $config -Name "disableDefenderRealtime") -or (Test-WindowsSecurityOptionEnabled -Config $config -Name "disableDefenderScheduledTasks"))) {
    throw "Options securite sensibles demandees : lance l'interface graphique pour confirmer avant application."
  }

  Write-SessionPlanReport -Mode "LANCEMENT" -Apps $selectedApps
  Apply-AudioEnvironment -Config $config
  Start-SelectedApps -Apps $selectedApps

  Write-Log "=== SESSION AUDIO PRETE ==="
  Write-Log "Rapport disponible dans : $script:LogFile"
  Write-Log "Script Mamat"
  Write-Log "Fin du script"
}
catch {
  try { Write-Log ("ERREUR : " + $_.Exception.Message) } catch {}
  throw
}
