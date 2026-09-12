; LoeBalance Windows installer (Inno Setup 6).
;
; Build with:
;   ISCC.exe /DSourceDir=<publish folder> /DRid=win-x64 /DAppVersion=0.1.0 LoeBalance.iss
;
; The result is a per-user install (no administrator rights) that matches the layout already
; used by the portable build: %LOCALAPPDATA%\Programs\LoeBalance.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#ifndef Rid
  #define Rid "win-x64"
#endif

#ifndef SourceDir
  #define SourceDir "..\..\work\publish\win-x64"
#endif

#ifndef OutputDir
  #define OutputDir "..\..\work\installer"
#endif

#define AppName "LoeBalance"
#define AppExe "LoeBalance.Desktop.Wpf.exe"
#define AppPublisher "7258AL1S"
#define AppUrl "https://github.com/7258AL1S/LoeBalance"

[Setup]
AppId={{8D2F4A01-6C4B-4F2E-9E51-7B1C5A2D3E10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion} ({#Rid})
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppUrl}
DefaultDirName={localappdata}\Programs\LoeBalance
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=LoeBalance-Setup-{#AppVersion}-{#Rid}
SetupIconFile=LoeBalance.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName} {#AppVersion} ({#Rid})
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
; No AppMutex on purpose: its pre-install "application is running" check cancels silent
; installs (/SUPPRESSMSGBOXES defaults to Cancel). PrepareToInstall below closes the tray app
; explicitly instead, which works for both interactive and silent installs.
#if Rid == "win-x64"
ArchitecturesAllowed=x64compatible
#else
ArchitecturesAllowed=x86compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
; Opt-in only: the app owns this setting through Settings -> Launch at Login.
Name: "startup"; Description: "Start LoeBalance when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; The app manages this value itself from Settings; the installer can start the same entry.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; \
  ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"""; Tasks: startup; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\VERSION.txt"
Type: filesandordirs; Name: "{app}"

[Code]
var
  RemoveUserData: Boolean;
  KillResultCode: Integer;

// The tray app keeps running when its windows are closed, and Restart Manager cannot always
// shut it down, so close it explicitly before files are replaced.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  NeedsRestart := False;
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#AppExe} /F', '', SW_HIDE, ewWaitUntilTerminated, KillResultCode);
  Result := '';
end;

function InitializeUninstall(): Boolean;
var
  Response: Integer;
begin
  Result := True;
  // Close the tray app first: it keeps running with its windows closed, and the uninstaller
  // cannot delete a locked executable.
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/IM {#AppExe} /F', '', SW_HIDE, ewWaitUntilTerminated, KillResultCode);
  if UninstallSilent then
  begin
    // Silent uninstalls keep user data unless the caller removes it explicitly.
    RemoveUserData := False;
  end
  else
  begin
    Response := MsgBox(
      'Also delete your LoeBalance settings, the cached balance and the saved sign-in credential?' + #13#10 + #13#10 +
      'Choose No to keep them for a later reinstall.',
      mbConfirmation, MB_YESNO or MB_DEFBUTTON2);
    RemoveUserData := Response = IDYES;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  CmdKeyResultCode: Integer;
begin
  if (CurUninstallStep = usUninstall) and RemoveUserData then
  begin
    DelTree(ExpandConstant('{localappdata}\LoeBalance'), True, True, True);
    Exec(ExpandConstant('{sys}\cmdkey.exe'), '/delete:LoeBalance:sub2api-refresh-token', '', SW_HIDE, ewWaitUntilTerminated, CmdKeyResultCode);
  end;
end;
