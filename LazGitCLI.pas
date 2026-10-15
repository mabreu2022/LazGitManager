unit LazGitCLI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Process,
  // IDEIntf
  LazIDEIntf, SrcEditorIntf,
  // Local config
  LazGitHubConfig;

type
  { TLazGitRunner }

  TLazGitRunner = class
  private
    FLastError: string;
    FLastExitCode: Integer;
    FExplicitWorkingDir: string;

    function GetGitExecutable: string;
    function RunCommand(const AArgs: array of string; out AOutput: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function HasActiveProject: Boolean;
    function GetProjectDir: string;

    function GetStatus(out AStaged, AUnstaged: TStrings): Boolean;
    function StageFile(const AFilename: string): Boolean;
    function UnstageFile(const AFilename: string): Boolean;
    function DiscardFile(const AFilename: string; AIsUntracked: Boolean = False): Boolean;
    function StageAll: Boolean;
    function UnstageAll: Boolean;
    function Commit(const AMessage: string): Boolean;
    function Push(const ARemote, ABranch: string): string;
    function Pull(const ARemote, ABranch: string): string;
    function GetCurrentBranch: string;
    function GetDiff(const AFilename: string; AStaged: Boolean = False): string;
    function GetRemoteURL(const ARemote: string = 'origin'): string;
    function ParseOwnerAndRepo(const ARemoteURL: string; out AOwner, ARepo: string): Boolean;
    function InitRepo: Boolean;
    function IsRepoInitialized: Boolean;
    function SetRemoteURL(const ARemoteURL: string; const ARemote: string = 'origin'): Boolean;

    property ExplicitWorkingDir: string read FExplicitWorkingDir write FExplicitWorkingDir;
    property LastError: string read FLastError;
    property LastExitCode: Integer read FLastExitCode;
  end;

implementation

{ TLazGitRunner }

constructor TLazGitRunner.Create;
begin
  inherited Create;
  FLastError := '';
  FLastExitCode := 0;
  FExplicitWorkingDir := '';
end;

destructor TLazGitRunner.Destroy;
begin
  inherited Destroy;
end;

function TLazGitRunner.GetGitExecutable: string;
begin
  Result := Trim(GitHubConfig.GitExecutablePath);
  if Result = '' then
    Result := DefaultGitExecutable;
end;

function TLazGitRunner.HasActiveProject: Boolean;
begin
  Result := (GetProjectDir <> '');
end;

function TLazGitRunner.GetProjectDir: string;
begin
  Result := '';

  // 1. Explicit working directory if manually chosen
  if (FExplicitWorkingDir <> '') and DirectoryExists(FExplicitWorkingDir) then
    Exit(FExplicitWorkingDir);

  // 2. Active Lazarus Project (.lpi or main source)
  if Assigned(LazarusIDE) and Assigned(LazarusIDE.ActiveProject) then
  begin
    if LazarusIDE.ActiveProject.ProjectInfoFile <> '' then
      Result := ExtractFileDir(LazarusIDE.ActiveProject.ProjectInfoFile)
    else if LazarusIDE.ActiveProject.MainFile <> nil then
      Result := ExtractFileDir(LazarusIDE.ActiveProject.MainFile.Filename);
  end;

  // 3. Fallback: Folder of the file currently active in the IDE editor
  if (Result = '') and Assigned(SourceEditorManagerIntf) and Assigned(SourceEditorManagerIntf.ActiveEditor) then
  begin
    if SourceEditorManagerIntf.ActiveEditor.FileName <> '' then
      Result := ExtractFileDir(SourceEditorManagerIntf.ActiveEditor.FileName);
  end;
end;

function TLazGitRunner.RunCommand(const AArgs: array of string; out AOutput: string): Boolean;
var
  Proc: TProcess;
  I: Integer;
  WorkingDir: string;
  MemStream: TMemoryStream;
  Buffer: array[0..4095] of Byte;
  BytesRead: Integer;
begin
  Result := False;
  AOutput := '';
  FLastError := '';
  FLastExitCode := -1;

  WorkingDir := GetProjectDir;
  if WorkingDir = '' then
  begin
    FLastError := 'No active project loaded in Lazarus IDE. Please open a project first.';
    Exit;
  end;

  if not DirectoryExists(WorkingDir) then
  begin
    FLastError := 'Active project directory does not exist: ' + WorkingDir;
    Exit;
  end;

  Proc := TProcess.Create(nil);
  MemStream := TMemoryStream.Create;
  try
    Proc.Executable := GetGitExecutable;
    Proc.CurrentDirectory := WorkingDir;
    for I := Low(AArgs) to High(AArgs) do
      Proc.Parameters.Add(AArgs[I]);

    // Use pipes with merged stderr to avoid stdout/stderr deadlock
    Proc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];

    try
      Proc.Execute;
    except
      on E: Exception do
      begin
        FLastError := 'Failed to launch Git process: ' + E.Message + LineEnding +
          'Verify that Git is installed and configured under Tools > Options > Version Control.';
        Exit(False);
      end;
    end;

    // Pump output safely while process executes
    while Proc.Running do
    begin
      while Proc.Output.NumBytesAvailable > 0 do
      begin
        BytesRead := Proc.Output.Read(Buffer[0], Min(SizeOf(Buffer), Proc.Output.NumBytesAvailable));
        if BytesRead > 0 then
          MemStream.Write(Buffer[0], BytesRead);
      end;
      Application.ProcessMessages;
      Sleep(10);
    end;

    // Read any remaining output bytes after process termination
    while Proc.Output.NumBytesAvailable > 0 do
    begin
      BytesRead := Proc.Output.Read(Buffer[0], Min(SizeOf(Buffer), Proc.Output.NumBytesAvailable));
      if BytesRead > 0 then
        MemStream.Write(Buffer[0], BytesRead);
    end;

    FLastExitCode := Proc.ExitCode;
    SetLength(AOutput, MemStream.Size);
    if MemStream.Size > 0 then
    begin
      MemStream.Position := 0;
      MemStream.Read(AOutput[1], MemStream.Size);
    end;

    Result := (FLastExitCode = 0);
    if not Result then
      FLastError := Trim(AOutput);
  finally
    MemStream.Free;
    Proc.Free;
  end;
end;

function TLazGitRunner.GetStatus(out AStaged, AUnstaged: TStrings): Boolean;
var
  RawOutput: string;
  Lines: TStringList;
  I: Integer;
  Line, FileName: string;
  IndexStatus, WorkTreeStatus: Char;
begin
  Result := False;
  AStaged := TStringList.Create;
  AUnstaged := TStringList.Create;

  if not HasActiveProject then
  begin
    FLastError := 'No active project loaded in Lazarus IDE.';
    Exit;
  end;

  // Run git status --porcelain -uall to get full list of modified and untracked files
  if not RunCommand(['status', '--porcelain', '-uall'], RawOutput) then
    Exit;

  Lines := TStringList.Create;
  try
    Lines.Text := RawOutput;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      if Length(Line) >= 4 then
      begin
        IndexStatus := Line[1];
        WorkTreeStatus := Line[2];
        FileName := Copy(Line, 4, Length(Line));

        // Trim possible outer quotes added by Git for filenames with spaces
        if (Length(FileName) >= 2) and (FileName[1] = '"') and (FileName[Length(FileName)] = '"') then
          FileName := Copy(FileName, 2, Length(FileName) - 2);

        // Staged changes (Index contains changes)
        if IndexStatus in ['M', 'A', 'D', 'R', 'C'] then
          AStaged.Add(IndexStatus + #9 + FileName);

        // Unstaged changes (Working Tree contains modifications, deletions, or untracked)
        if WorkTreeStatus in ['M', 'D'] then
          AUnstaged.Add(WorkTreeStatus + #9 + FileName)
        else if (IndexStatus = '?') and (WorkTreeStatus = '?') then
          AUnstaged.Add('?' + #9 + FileName);
      end;
    end;
    Result := True;
  finally
    Lines.Free;
  end;
end;

function TLazGitRunner.StageFile(const AFilename: string): Boolean;
var
  OutStr: string;
begin
  Result := RunCommand(['add', '--', AFilename], OutStr);
end;

function TLazGitRunner.UnstageFile(const AFilename: string): Boolean;
var
  OutStr: string;
begin
  Result := RunCommand(['reset', 'HEAD', '--', AFilename], OutStr);
end;

function TLazGitRunner.DiscardFile(const AFilename: string; AIsUntracked: Boolean): Boolean;
var
  OutStr: string;
begin
  if AIsUntracked then
    Result := RunCommand(['clean', '-f', '--', AFilename], OutStr)
  else
    Result := RunCommand(['checkout', '--', AFilename], OutStr);
end;

function TLazGitRunner.StageAll: Boolean;
var
  OutStr: string;
begin
  Result := RunCommand(['add', '-A'], OutStr);
end;

function TLazGitRunner.UnstageAll: Boolean;
var
  OutStr: string;
begin
  Result := RunCommand(['reset', 'HEAD'], OutStr);
end;

function TLazGitRunner.Commit(const AMessage: string): Boolean;
var
  OutStr: string;
begin
  if Trim(AMessage) = '' then
  begin
    FLastError := 'Commit message cannot be empty.';
    Exit(False);
  end;

  Result := RunCommand(['commit', '-m', AMessage], OutStr);
end;

function TLazGitRunner.Push(const ARemote, ABranch: string): string;
var
  OutStr: string;
begin
  Result := '';
  if (ARemote <> '') and (ABranch <> '') then
    RunCommand(['push', ARemote, ABranch], OutStr)
  else if ARemote <> '' then
    RunCommand(['push', ARemote], OutStr)
  else
    RunCommand(['push'], OutStr);
  Result := OutStr;
end;

function TLazGitRunner.Pull(const ARemote, ABranch: string): string;
var
  OutStr: string;
begin
  Result := '';
  if (ARemote <> '') and (ABranch <> '') then
    RunCommand(['pull', ARemote, ABranch], OutStr)
  else if ARemote <> '' then
    RunCommand(['pull', ARemote], OutStr)
  else
    RunCommand(['pull'], OutStr);
  Result := OutStr;
end;

function TLazGitRunner.GetCurrentBranch: string;
var
  OutStr: string;
begin
  Result := '';
  if RunCommand(['rev-parse', '--abbrev-ref', 'HEAD'], OutStr) then
    Result := Trim(OutStr);
end;

function TLazGitRunner.GetDiff(const AFilename: string; AStaged: Boolean): string;
var
  OutStr: string;
begin
  Result := '';
  if AStaged then
  begin
    if AFilename <> '' then
      RunCommand(['diff', '--staged', '--', AFilename], OutStr)
    else
      RunCommand(['diff', '--staged'], OutStr);
  end
  else
  begin
    if AFilename <> '' then
      RunCommand(['diff', '--', AFilename], OutStr)
    else
      RunCommand(['diff'], OutStr);
  end;
  Result := OutStr;
end;

function TLazGitRunner.GetRemoteURL(const ARemote: string): string;
var
  RemoteName, OutStr: string;
begin
  Result := '';
  RemoteName := ARemote;
  if RemoteName = '' then
    RemoteName := 'origin';

  if RunCommand(['config', '--get', 'remote.' + RemoteName + '.url'], OutStr) then
    Result := Trim(OutStr);
end;

function TLazGitRunner.ParseOwnerAndRepo(const ARemoteURL: string; out AOwner, ARepo: string): Boolean;
var
  S: string;
  SlashPos, ColonPos: Integer;
begin
  Result := False;
  AOwner := '';
  ARepo := '';
  S := Trim(ARemoteURL);
  if S = '' then
    Exit;

  // Remove trailing .git
  if LowerCase(Copy(S, Length(S) - 3, 4)) = '.git' then
    S := Copy(S, 1, Length(S) - 4);

  // Handle SSH format: git@github.com:owner/repo
  ColonPos := Pos(':', S);
  if (Pos('git@', S) = 1) and (ColonPos > 0) then
    S := Copy(S, ColonPos + 1, Length(S))
  // Handle HTTPS format: https://github.com/owner/repo
  else if Pos('github.com/', S) > 0 then
    S := Copy(S, Pos('github.com/', S) + 11, Length(S));

  SlashPos := Pos('/', S);
  if SlashPos > 0 then
  begin
    AOwner := Copy(S, 1, SlashPos - 1);
    ARepo := Copy(S, SlashPos + 1, Length(S));
    Result := (AOwner <> '') and (ARepo <> '');
  end;
end;

function TLazGitRunner.IsRepoInitialized: Boolean;
var
  PDir: string;
begin
  PDir := GetProjectDir;
  Result := (PDir <> '') and DirectoryExists(PDir + DirectorySeparator + '.git');
end;

function TLazGitRunner.InitRepo: Boolean;
var
  OutStr: string;
begin
  // Try initializing with main as default branch
  Result := RunCommand(['init', '-b', 'main'], OutStr);
  if not Result then
  begin
    // Older Git versions fallback
    Result := RunCommand(['init'], OutStr);
    if Result then
      RunCommand(['symbolic-ref', 'HEAD', 'refs/heads/main'], OutStr);
  end;
  if not Result then
    FLastError := 'Failed to initialize Git repository: ' + FLastError;
end;

function TLazGitRunner.SetRemoteURL(const ARemoteURL: string; const ARemote: string): Boolean;
var
  OutStr: string;
  RemoteName: string;
begin
  RemoteName := ARemote;
  if RemoteName = '' then
    RemoteName := 'origin';

  // If this directory is not yet a git repository, initialize it first (git init)
  if not IsRepoInitialized then
  begin
    if not InitRepo then
      Exit(False);
  end;

  // If remote already exists, update with set-url; otherwise add it
  if (GetRemoteURL(RemoteName) <> '') then
    Result := RunCommand(['remote', 'set-url', RemoteName, ARemoteURL], OutStr)
  else
    Result := RunCommand(['remote', 'add', RemoteName, ARemoteURL], OutStr);
end;

end.
