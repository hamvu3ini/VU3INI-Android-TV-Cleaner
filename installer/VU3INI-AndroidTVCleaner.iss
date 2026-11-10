; VU3INI Android TV Cleaner - Inno Setup script
; Compiled by build\Build-Installer.ps1, which passes /DStageDir, /DOutputDir and /DAppVersion.

#ifndef StageDir
  #define StageDir "C:\VU3INI-build\stage"
#endif
#ifndef OutputDir
  #define OutputDir "..\output"
#endif
#ifndef AppVersion
  #define AppVersion "2.0"
#endif

#define AppName "VU3INI Android TV Cleaner"
#define AppExe  "VU3INI Android TV Cleaner.exe"

[Setup]
AppId={{6B8E3C52-1F4D-4E7A-9A3B-5C2D1E0F9A31}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=VU3INI (Sasanka Boruah)
AppContact=hamvu3ini@gmail.com
AppComments=Offline Step 2 toolchain for CleanYourTV (Android TV / Google TV debloat)
VersionInfoVersion={#AppVersion}.0.0
VersionInfoCompany=VU3INI
VersionInfoDescription={#AppName} Setup
; No spaces in the default path: Gradle and the Android SDK prefer it. No admin rights needed.
DefaultDirName=C:\VU3INI\ATVCleaner
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if Ver >= 0x06030000
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#else
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
#endif
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=VU3INI-Android-TV-Cleaner-Setup-{#AppVersion}
SetupIconFile={#StageDir}\assets\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
LZMANumBlockThreads=4
DiskSpanning=no
ExtraDiskSpaceRequired=600000000
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autoprograms}\{#AppName} - CleanYourTV PowerShell"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; \
  Parameters: "-NoExit -NoProfile -ExecutionPolicy Bypass -File ""{app}\Open-CleanYourTV-Shell.ps1"""; \
  WorkingDir: "{app}\cleanyourtv"; IconFilename: "{app}\assets\app.ico"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Parameters: "--setup"; Description: "Launch {#AppName} and finish Step 2 setup"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; Stop a Gradle daemon left running so its files can be removed.
Filename: "{cmd}"; Parameters: "/d /c set ""JAVA_HOME={app}\jdk"" && set ""GRADLE_USER_HOME={app}\gradle-home"" && gradlew.bat --stop"; \
  WorkingDir: "{app}\cleanyourtv\launcher"; Flags: runhidden; RunOnceId: "StopGradleDaemon"

[UninstallDelete]
; Files created after installation (venv, build outputs, Gradle's runtime caches).
Type: filesandordirs; Name: "{app}\cleanyourtv\tools\venv"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\app\build"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\build"
Type: filesandordirs; Name: "{app}\cleanyourtv\launcher\.gradle"
Type: files;          Name: "{app}\cleanyourtv\launcher\local.properties"
Type: filesandordirs; Name: "{app}\gradle-home"
Type: files;          Name: "{app}\setup-done.txt"
Type: filesandordirs; Name: "{app}\python\Lib\__pycache__"

[Code]
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    if Pos(' ', WizardDirValue) > 0 then
    begin
      MsgBox('Please choose a folder without spaces (for example C:\VU3INI\ATVCleaner).' + #13#10 +
             'Gradle and the Android SDK do not work reliably from paths with spaces.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;
