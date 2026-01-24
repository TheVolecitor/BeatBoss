[Setup]
; Basic Information
AppName=BeatBoss (FFmpeg Version)
AppVersion=1.2
AppPublisher=TheVolecitor
DefaultDirName={autopf}\BeatBoss_FFmpeg
DefaultGroupName=BeatBoss FFmpeg
OutputBaseFilename=BeatBoss_FFmpeg_Installer_v1.2
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

[Files]
; Main Executable and Bundle from the FFmpeg specific dist folder
; NOTE: You must run "pyinstaller beatboss_ffmpeg.spec" first!
Source: "dist\BeatBoss_FFmpeg\BeatBoss_FFmpeg.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\BeatBoss_FFmpeg\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BeatBoss FFmpeg"; Filename: "{app}\BeatBoss_FFmpeg.exe"; IconFilename: "{app}\assets\icon.ico"
Name: "{group}\Uninstall BeatBoss FFmpeg"; Filename: "{uninstallexe}"
Name: "{autodesktop}\BeatBoss FFmpeg"; Filename: "{app}\BeatBoss_FFmpeg.exe"; Tasks: desktopicon; IconFilename: "{app}\assets\icon.ico"

[Run]
Filename: "{app}\BeatBoss_FFmpeg.exe"; Description: "Launch BeatBoss (FFmpeg)"; Flags: nowait postinstall skipifsilent

[Dirs]
Name: "{userappdata}\BeatBoss"

[Code]
// FFmpeg binaries are bundled in the 'ffmpeg' subfolder by PyInstaller
