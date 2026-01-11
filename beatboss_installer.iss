[Setup]
; Basic Information
AppName=BeatBoss
AppVersion=1.0
AppPublisher=BeatBoss Team

DefaultDirName={autopf}\BeatBoss
DefaultGroupName=BeatBoss
OutputBaseFilename=BeatBoss_Installer
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=assets\icon.ico
; Prevent duplicate installs
DisableProgramGroupPage=yes
LicenseFile=license.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "taskbaricon"; Description: "Pin to Taskbar"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Main Executable and Bundle
; NOTE: You must run PyInstaller first to generate these files!
Source: "dist\BeatBoss\BeatBoss.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\BeatBoss\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Explicitly copy assets folder so shortcuts can find the icon
Source: "assets\*"; DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BeatBoss"; Filename: "{app}\BeatBoss.exe"; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\Uninstall BeatBoss"; Filename: "{uninstallexe}"
Name: "{autodesktop}\BeatBoss"; Filename: "{app}\BeatBoss.exe"; Tasks: desktopicon; IconFilename: "{app}\assets\icon.ico"
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\BeatBoss"; Filename: "{app}\BeatBoss.exe"; Tasks: taskbaricon; IconFilename: "{app}\assets\icon.ico"

[Run]
Filename: "{app}\BeatBoss.exe"; Description: "{cm:LaunchProgram,BeatBoss}"; Flags: nowait postinstall skipifsilent

[Dirs]
; Ensure local data dir exists (optional, app handles it)
Name: "{userappdata}\BeatBoss"

[Code]
function InitializeSetup(): Boolean;
var
  ErrCode: Integer;
begin
  Result := True;
  // Check for VLC 32-bit and 64-bit registry keys
  if not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\VideoLAN\VLC') and
     not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\WOW6432Node\VideoLAN\VLC') then
  begin
    if MsgBox('BeatBoss requires VLC Media Player, which was not detected.' + #13#10 +
              'Do you want to download and install it now?', mbConfirmation, MB_YESNO) = idYes then
    begin
      // Open VLC download page
      ShellExec('open', 'https://www.videolan.org/vlc/', '', '', SW_SHOW, ewNoWait, ErrCode);
      MsgBox('Please install VLC and then run this setup again.', mbInformation, MB_OK);
      Result := False; // Abort installation
    end
    else
    begin
      if MsgBox('The app may not play audio without VLC. Continue anyway?', mbConfirmation, MB_YESNO) = idNo then
        Result := False;
    end;
  end;
end;
