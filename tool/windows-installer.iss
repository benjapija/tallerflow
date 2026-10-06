; Build only on the Windows GitHub runner. Pilot installer: no signing yet.
[Setup]
AppId={{118D38C1-82F3-40DD-879C-5055AF16B591}
AppName=TallerFlow (piloto)
AppVersion=0.2.0
DefaultDirName={localappdata}\Programs\TallerFlow
DefaultGroupName=TallerFlow
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=TallerFlow-Setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\tallerflow.exe
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\TallerFlow"; Filename: "{app}\tallerflow.exe"
[Registry]
Root: HKCU; Subkey: "Software\Classes\tallerflow"; ValueType: string; ValueData: "URL:TallerFlow"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\tallerflow"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\tallerflow\shell\open\command"; ValueType: string; ValueData: """{app}\tallerflow.exe"" ""%1"""
[Run]
Filename: "{app}\tallerflow.exe"; Description: "Abrir TallerFlow"; Flags: nowait postinstall skipifsilent
