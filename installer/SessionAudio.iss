; SessionAudio.iss
; Installe Session Audio, ses raccourcis et sa restauration reversible.
; By Mamat

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{64D237AF-33FD-49AB-BC54-5E0041967D3F}
AppName=Session Audio
AppVersion={#AppVersion}
AppVerName=Session Audio {#AppVersion}
AppPublisher=Mamat
AppPublisherURL=https://github.com/Mamat79/Session-Audio
AppSupportURL=https://github.com/Mamat79/Session-Audio/issues
AppUpdatesURL=https://github.com/Mamat79/Session-Audio/releases
DefaultDirName={localappdata}\Programs\Session Audio
DefaultGroupName=Session Audio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=output
OutputBaseFilename=Session-Audio-Setup-{#AppVersion}
SetupIconFile=..\Session_Audio.ico
UninstallDisplayIcon={app}\SessionAudioLauncher.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0.17763
ArchitecturesAllowed=x64compatible
CloseApplications=no
RestartApplications=no
SetupLogging=yes
UsePreviousAppDir=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=Mamat
VersionInfoDescription=Gestionnaire reversible de session audio Windows
VersionInfoProductName=Session Audio
VersionInfoProductVersion={#AppVersion}

[Tasks]
Name: "desktopicon"; Description: "Creer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: checkedonce

[Dirs]
Name: "{app}\Logs"; Flags: uninsneveruninstall

[Files]
Source: "..\Audio-Live.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\SessionAudioLauncher.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\Audio-Live.apps.bootstrap.json"; DestDir: "{app}"; DestName: "Audio-Live.apps.json"; Flags: onlyifdoesntexist uninsneveruninstall
Source: "..\Audio-Live.apps.example.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Mode_Audio.pow"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Session_Audio.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALLATION.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SECURITY.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\RESTORE.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSION"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Session Audio"; Filename: "{app}\SessionAudioLauncher.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Session_Audio.ico"; Comment: "Preparer le poste pour une session audio"
Name: "{autoprograms}\Session Audio - Restaurer"; Filename: "{app}\SessionAudioLauncher.exe"; Parameters: "--restore"; WorkingDir: "{app}"; IconFilename: "{app}\Session_Audio.ico"; Comment: "Restaurer l'etat Windows precedent"
Name: "{autoprograms}\Session Audio - Configuration"; Filename: "{app}\SessionAudioLauncher.exe"; Parameters: "--open-config"; WorkingDir: "{app}"; IconFilename: "{app}\Session_Audio.ico"; Comment: "Ouvrir la configuration Session Audio"
Name: "{autodesktop}\Session Audio"; Filename: "{app}\SessionAudioLauncher.exe"; WorkingDir: "{app}"; IconFilename: "{app}\Session_Audio.ico"; Tasks: desktopicon; Comment: "Preparer le poste pour une session audio"

[Run]
Filename: "{app}\SessionAudioLauncher.exe"; Description: "Lancer Session Audio"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeUninstall(): Boolean;
var
  StatePath: String;
begin
  StatePath := ExpandConstant('{app}\Audio-Live.state.json');
  if FileExists(StatePath) then
  begin
    MsgBox(
      'Une session precedente doit encore etre restauree.' + #13#10 + #13#10 +
      'Lancez "Session Audio - Restaurer" avant de desinstaller le logiciel.',
      mbError,
      MB_OK);
    Result := False;
  end
  else
    Result := True;
end;
