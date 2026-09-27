; Inno Setup script for the signed Windows build.
;
; Windows needs an installer rather than a zip because WinSparkle updates by
; downloading the enclosure and *running* it — a .zip has nothing to run. It
; is also what makes an unsigned build survivable: Windows shows one
; SmartScreen prompt for the installer instead of one per launch.
;
; Built by .github/workflows/release.yml, which passes the version in:
;   iscc /DAppVersion=0.4.0 /DSourceDir=... /DOutputDir=... installer.iss

#define AppName "PinBench"
#define AppPublisher "Burhan Khanzada"
#define AppExeName "pinbench.exe"
#define AppUrl "https://pinbench.web.app"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Never change AppId. It is what tells Windows an install is an upgrade of
; the existing one rather than a second copy beside it — which is exactly
; what every WinSparkle update is.
AppId={{4F86BC2B-4262-4322-989D-F9AA86A5548E}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Per-user by default: a per-machine install needs elevation, and an update
; that prompts for an administrator password is an update most people cancel.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#OutputDir}
OutputBaseFilename=pinbench-{#AppVersion}-windows-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Surfaced in the Windows "Apps & features" list and read by WinSparkle.
VersionInfoVersion={#AppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; `nowait` and `skipifsilent` together are what make a WinSparkle update
; feel like an update: the silent re-install started by the updater must not
; block waiting for the app it just replaced.
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
