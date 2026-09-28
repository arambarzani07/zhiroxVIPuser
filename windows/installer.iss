#define MyAppName "ZHIROX User"
#define MyAppVersion "1.0.0"
#define MyAppExeName "zhirox.exe"

[Setup]
AppId={{CBA154C4-C9BB-4567-8E14-C7FC28FD086A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=ZHIROX
DefaultDirName={localappdata}\Programs\ZHIROX User
DefaultGroupName=ZHIROX User
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=ZHIROX-User-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\ZHIROX User"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\ZHIROX User"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch ZHIROX User"; Flags: nowait postinstall skipifsilent
