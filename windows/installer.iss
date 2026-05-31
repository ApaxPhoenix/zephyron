#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\bin"
#endif
#ifndef OutputName
  #define OutputName "zephyron-windows-x64-setup"
#endif

[Setup]
AppId={{DB07AC7C-15BF-448E-8EA8-5CCEACF448C1}
AppName=Zephyron
AppVersion={#AppVersion}
AppVerName=Zephyron {#AppVersion}
AppPublisher=Aveloux
AppPublisherURL=https://github.com/ApaxPhoenix/zephyron
DefaultDirName={autopf}\Zephyron
DefaultGroupName=Zephyron
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\zephyron.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Zephyron"; Filename: "{app}\zephyron.exe"
Name: "{autodesktop}\Zephyron"; Filename: "{app}\zephyron.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\zephyron.exe"; Description: "{cm:LaunchProgram,Zephyron}"; Flags: nowait postinstall skipifsilent
