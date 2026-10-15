unit LazGitDockForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls,
  StdCtrls, ExtCtrls, Menus, Buttons,
  // IDEIntf
  IDEWindowIntf, LazIDEIntf, ProjectIntf,
  // Local units
  LazGitHubConfig, LazGitHubAPI, LazGitCLI, LazGitHubOptionsFrame, LazGitRevertForm;

const
  LazGitDockFormName = 'LazGitDockViewForm';

type
  { TLazGitDockViewForm }

  TLazGitDockViewForm = class(TForm)
    // Top Action & Status Bar
    PanelTop: TPanel;
    PanelTopBar: TPanel;
    btnRefresh: TButton;
    lblBranchTitle: TLabel;
    lblBranch: TLabel;
    lblProjectTitle: TLabel;
    lblProject: TLabel;
    lblGitHubTitle: TLabel;
    lblGitHubUser: TLabel;

    // Commit sub-panel
    PanelCommit: TPanel;
    lblCommitTitle: TLabel;
    memoCommit: TMemo;
    PanelCommitButtons: TPanel;
    btnCommit: TButton;
    btnCommitPush: TButton;

    // Main Center Tabs
    PageControl: TPageControl;
    TabChanges: TTabSheet;
    TabGitHub: TTabSheet;

    // Tab 1: Git Changes
    PanelChangesBar: TPanel;
    btnStageAll: TButton;
    btnUnstageAll: TButton;
    btnDiff: TButton;
    btnDiscard: TButton;
    btnPull: TButton;
    btnPush: TButton;
    btnRevert: TButton;
    lvChanges: TListView;
    pmChanges: TPopupMenu;
    miStage: TMenuItem;
    miUnstage: TMenuItem;
    miDiff: TMenuItem;
    miDiscard: TMenuItem;
    miSep1: TMenuItem;
    miStageAll: TMenuItem;
    miUnstageAll: TMenuItem;

    // Tab 2: GitHub Remote
    PanelGitHubBar: TPanel;
    btnConnectGitHub: TButton;
    btnSettings: TButton;
    lblRepo: TLabel;
    cbRepos: TComboBox;
    btnSetRemote: TButton;

    PageControlGitHub: TPageControl;
    TabIssues: TTabSheet;
    TabPullRequest: TTabSheet;

    // Issue Controls
    lblIssueTitle: TLabel;
    edtIssueTitle: TEdit;
    lblIssueBody: TLabel;
    memoIssueBody: TMemo;
    btnCreateIssue: TButton;

    // PR Controls
    lblPRTitle: TLabel;
    edtPRTitle: TEdit;
    lblPRHead: TLabel;
    edtPRHead: TEdit;
    lblPRBase: TLabel;
    edtPRBase: TEdit;
    lblPRBody: TLabel;
    memoPRBody: TMemo;
    btnCreatePR: TButton;

    // Bottom Log Panel
    SplitterLog: TSplitter;
    PanelLog: TPanel;
    lblLog: TLabel;
    memoLog: TMemo;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);

    procedure btnRefreshClick(Sender: TObject);
    procedure btnCommitClick(Sender: TObject);
    procedure btnCommitPushClick(Sender: TObject);
    procedure btnStageAllClick(Sender: TObject);
    procedure btnUnstageAllClick(Sender: TObject);
    procedure btnDiffClick(Sender: TObject);
    procedure btnDiscardClick(Sender: TObject);
    procedure btnPullClick(Sender: TObject);
    procedure btnPushClick(Sender: TObject);
    procedure btnRevertClick(Sender: TObject);
    procedure lvChangesItemChecked(Sender: TObject; Item: TListItem);

    procedure miStageClick(Sender: TObject);
    procedure miUnstageClick(Sender: TObject);
    procedure miDiffClick(Sender: TObject);
    procedure miDiscardClick(Sender: TObject);
    procedure miStageAllClick(Sender: TObject);
    procedure miUnstageAllClick(Sender: TObject);

    procedure btnConnectGitHubClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure btnSetRemoteClick(Sender: TObject);
    procedure btnCreateIssueClick(Sender: TObject);
    procedure btnCreatePRClick(Sender: TObject);
    procedure cbReposChange(Sender: TObject);
  private
    FGitRunner: TLazGitRunner;
    FGitHubClient: TLazGitHubClient;
    FUpdatingList: Boolean;

    procedure LogMessage(const AMsg: string);
    function FormatStatusText(const AStatusCode: Char): string;
    function GetSelectedFilePath(out AIsStaged: Boolean; out AIsUntracked: Boolean): string;
    procedure RefreshStatus;
    procedure AutoDetectRemoteRepo;
    procedure UpdateGitHubStatusDisplay;
    procedure RepositionTopBarLabels;
    function OnProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
    function OnProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
    procedure HandleConfigChanged(Sender: TObject);
  public
    procedure RefreshUI;
  end;

var
  LazGitDockViewFormInstance: TLazGitDockViewForm = nil;

procedure CreateLazGitDockViewForm(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
procedure ShowLazGitDockForm;

implementation

{$R *.lfm}

procedure CreateLazGitDockViewForm(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if LazGitDockViewFormInstance = nil then
  begin
    IDEWindowCreators.CreateForm(AForm, TLazGitDockViewForm, DoDisableAutoSizing, Application);
    LazGitDockViewFormInstance := TLazGitDockViewForm(AForm);
  end
  else
    AForm := LazGitDockViewFormInstance;
end;

procedure ShowLazGitDockForm;
begin
  IDEWindowCreators.ShowForm(LazGitDockFormName, True);
end;

{ TLazGitDockViewForm }

procedure TLazGitDockViewForm.FormCreate(Sender: TObject);
begin
  FGitRunner := TLazGitRunner.Create;
  FGitHubClient := TLazGitHubClient.Create;
  FUpdatingList := False;

  GitHubConfig.OnChange := @HandleConfigChanged;
  if Assigned(LazarusIDE) then
  begin
    LazarusIDE.AddHandlerOnProjectOpened(@OnProjectOpened);
    LazarusIDE.AddHandlerOnProjectClose(@OnProjectClose);
  end;

  LogMessage('LazGitHubIntegration dockable view initialized.');
  RefreshUI;
end;

procedure TLazGitDockViewForm.FormDestroy(Sender: TObject);
begin
  if LazGitDockViewFormInstance = Self then
    LazGitDockViewFormInstance := nil;

  if Assigned(LazarusIDE) then
  begin
    LazarusIDE.RemoveHandlerOnProjectOpened(@OnProjectOpened);
    LazarusIDE.RemoveHandlerOnProjectClose(@OnProjectClose);
  end;

  GitHubConfig.OnChange := nil;

  FreeAndNil(FGitRunner);
  FreeAndNil(FGitHubClient);
end;

function TLazGitDockViewForm.OnProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
begin
  RefreshUI;
  Result := mrOk;
end;

function TLazGitDockViewForm.OnProjectClose(Sender: TObject; AProject: TLazProject): TModalResult;
begin
  RefreshUI;
  Result := mrOk;
end;

procedure TLazGitDockViewForm.HandleConfigChanged(Sender: TObject);
begin
  UpdateGitHubStatusDisplay;
end;

procedure TLazGitDockViewForm.RepositionTopBarLabels;
begin
  // Flow nicely: Refresh Button -> Project -> Branch -> GitHub
  lblProjectTitle.Left := btnRefresh.Left + btnRefresh.Width + 12;
  lblProject.Left := lblProjectTitle.Left + lblProjectTitle.Width + 4;

  lblBranchTitle.Left := lblProject.Left + lblProject.Width + 16;
  lblBranch.Left := lblBranchTitle.Left + lblBranchTitle.Width + 4;

  lblGitHubTitle.Left := lblBranch.Left + lblBranch.Width + 16;
  lblGitHubUser.Left := lblGitHubTitle.Left + lblGitHubTitle.Width + 4;
end;

procedure TLazGitDockViewForm.UpdateGitHubStatusDisplay;
begin
  GitHubConfig.LoadConfig;
  if Trim(GitHubConfig.GitHubToken) = '' then
  begin
    lblGitHubUser.Caption := 'Disconnected';
    lblGitHubUser.Font.Color := clMaroon;
  end
  else
  begin
    if GitHubConfig.GitHubUser <> '' then
      lblGitHubUser.Caption := '@' + GitHubConfig.GitHubUser
    else
      lblGitHubUser.Caption := 'Connected';
    lblGitHubUser.Font.Color := clGreen;
  end;
  RepositionTopBarLabels;
end;

procedure TLazGitDockViewForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Dockable IDE forms are hidden to preserve docking layout geometry
  CloseAction := caHide;
end;

procedure TLazGitDockViewForm.LogMessage(const AMsg: string);
var
  Timestamp: string;
begin
  Timestamp := FormatDateTime('hh:nn:ss', Now);
  memoLog.Lines.Add(Format('[%s] %s', [Timestamp, AMsg]));
  memoLog.SelStart := Length(memoLog.Text);
end;

function TLazGitDockViewForm.FormatStatusText(const AStatusCode: Char): string;
begin
  case AStatusCode of
    'M': Result := 'Modified';
    'A': Result := 'Added';
    'D': Result := 'Deleted';
    'R': Result := 'Renamed';
    'C': Result := 'Copied';
    '?': Result := 'Untracked';
    '!': Result := 'Ignored';
  else
    Result := 'Status ' + AStatusCode;
  end;
end;

procedure TLazGitDockViewForm.RefreshUI;
begin
  UpdateGitHubStatusDisplay;
  RefreshStatus;
  AutoDetectRemoteRepo;
end;

procedure TLazGitDockViewForm.RefreshStatus;
var
  StagedList, UnstagedList: TStrings;
  I, TabPos: Integer;
  Line, StatusCode, FileName: string;
  Item: TListItem;
  CurBranch: string;
begin
  if not FGitRunner.HasActiveProject then
  begin
    lblProject.Caption := '(None Open)';
    lblBranch.Caption := '-';
    btnRefresh.Enabled := False;
    btnCommit.Enabled := False;
    btnCommitPush.Enabled := False;
    btnStageAll.Enabled := False;
    btnUnstageAll.Enabled := False;
    btnDiff.Enabled := False;
    btnDiscard.Enabled := False;
    btnPull.Enabled := False;
    btnPush.Enabled := False;
    btnRevert.Enabled := False;
    lvChanges.Items.Clear;
    RepositionTopBarLabels;
    Exit;
  end;

  if Assigned(LazarusIDE.ActiveProject) and (LazarusIDE.ActiveProject.ProjectInfoFile <> '') then
    lblProject.Caption := ExtractFileName(LazarusIDE.ActiveProject.ProjectInfoFile)
  else if FGitRunner.GetProjectDir <> '' then
    lblProject.Caption := ExtractFileName(FGitRunner.GetProjectDir)
  else
    lblProject.Caption := '(Unknown)';

  if not FGitRunner.IsRepoInitialized then
  begin
    lblBranch.Caption := '(uninitialized)';
    RepositionTopBarLabels;
    btnRefresh.Enabled := True;
    btnCommit.Enabled := False;
    btnCommitPush.Enabled := False;
    btnStageAll.Enabled := False;
    btnUnstageAll.Enabled := False;
    btnDiff.Enabled := False;
    btnDiscard.Enabled := False;
    btnPull.Enabled := False;
    btnPush.Enabled := False;
    btnRevert.Enabled := False;
    lvChanges.Items.Clear;
    Exit;
  end;

  btnRefresh.Enabled := True;
  btnCommit.Enabled := True;
  btnCommitPush.Enabled := True;
  btnStageAll.Enabled := True;
  btnUnstageAll.Enabled := True;
  btnDiff.Enabled := True;
  btnDiscard.Enabled := True;
  btnPull.Enabled := True;
  btnPush.Enabled := True;
  btnRevert.Enabled := True;

  CurBranch := FGitRunner.GetCurrentBranch;
  if CurBranch <> '' then
  begin
    lblBranch.Caption := CurBranch;
    edtPRHead.Text := CurBranch;
  end
  else
    lblBranch.Caption := '(Detached/Error)';

  RepositionTopBarLabels;

  StagedList := nil;
  UnstagedList := nil;
  FUpdatingList := True;
  try
    lvChanges.Items.BeginUpdate;
    try
      lvChanges.Items.Clear;

      if FGitRunner.GetStatus(StagedList, UnstagedList) then
      begin
        // Add staged changes first
        for I := 0 to StagedList.Count - 1 do
        begin
          Line := StagedList[I];
          TabPos := Pos(#9, Line);
          if TabPos > 0 then
          begin
            StatusCode := Copy(Line, 1, TabPos - 1);
            FileName := Copy(Line, TabPos + 1, Length(Line));
          end
          else
          begin
            StatusCode := 'M';
            FileName := Line;
          end;

          Item := lvChanges.Items.Add;
          if Length(StatusCode) > 0 then
            Item.Caption := FormatStatusText(StatusCode[1])
          else
            Item.Caption := 'Staged';

          Item.SubItems.Add('Yes');
          Item.SubItems.Add(FileName);
          Item.Checked := True;
        end;

        // Add unstaged changes
        for I := 0 to UnstagedList.Count - 1 do
        begin
          Line := UnstagedList[I];
          TabPos := Pos(#9, Line);
          if TabPos > 0 then
          begin
            StatusCode := Copy(Line, 1, TabPos - 1);
            FileName := Copy(Line, TabPos + 1, Length(Line));
          end
          else
          begin
            StatusCode := '?';
            FileName := Line;
          end;

          Item := lvChanges.Items.Add;
          if Length(StatusCode) > 0 then
            Item.Caption := FormatStatusText(StatusCode[1])
          else
            Item.Caption := 'Unstaged';

          Item.SubItems.Add('No');
          Item.SubItems.Add(FileName);
          Item.Checked := False;
        end;

        LogMessage(Format('Status updated: %d staged, %d unstaged changes.',
          [StagedList.Count, UnstagedList.Count]));
      end
      else
        LogMessage('Status error: ' + FGitRunner.LastError);
    finally
      lvChanges.Items.EndUpdate;
    end;
  finally
    FUpdatingList := False;
    StagedList.Free;
    UnstagedList.Free;
  end;
end;

procedure TLazGitDockViewForm.AutoDetectRemoteRepo;
var
  RemoteURL, RepoOwner, Repo: string;
begin
  if not FGitRunner.HasActiveProject then Exit;

  RemoteURL := FGitRunner.GetRemoteURL('origin');
  if RemoteURL <> '' then
  begin
    if FGitRunner.ParseOwnerAndRepo(RemoteURL, RepoOwner, Repo) then
    begin
      if cbRepos.Items.IndexOf(RepoOwner + '/' + Repo) < 0 then
        cbRepos.Items.Add(RepoOwner + '/' + Repo);
      cbRepos.Text := RepoOwner + '/' + Repo;
      LogMessage(Format('Detected repository from remote: %s/%s', [RepoOwner, Repo]));
    end;
  end;
end;

function TLazGitDockViewForm.GetSelectedFilePath(out AIsStaged: Boolean; out AIsUntracked: Boolean): string;
var
  Item: TListItem;
begin
  Result := '';
  AIsStaged := False;
  AIsUntracked := False;

  Item := lvChanges.Selected;
  if (Item <> nil) and (Item.SubItems.Count >= 2) then
  begin
    AIsStaged := (Item.SubItems[0] = 'Yes');
    Result := Item.SubItems[1];
    AIsUntracked := (Item.Caption = 'Untracked');
  end;
end;

procedure TLazGitDockViewForm.btnRefreshClick(Sender: TObject);
begin
  RefreshStatus;
end;

procedure TLazGitDockViewForm.btnCommitClick(Sender: TObject);
var
  Msg: string;
begin
  Msg := Trim(memoCommit.Text);
  if Msg = '' then
  begin
    MessageDlg('Commit Validation', 'Please enter a commit message before committing.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if FGitRunner.Commit(Msg) then
  begin
    LogMessage('Commit successful: ' + Msg);
    memoCommit.Clear;
    MessageDlg('Git Commit', 'Commit "' + Msg + '" successfully saved locally!' + LineEnding + LineEnding +
      'To upload this commit to GitHub, click the "Push" button.', mtInformation, [mbOK], 0);
    RefreshStatus;
  end
  else
  begin
    LogMessage('Commit failed: ' + FGitRunner.LastError);
    MessageDlg('Git Commit Error', FGitRunner.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TLazGitDockViewForm.btnCommitPushClick(Sender: TObject);
var
  Msg, PushOutput, CurBranch: string;
begin
  Msg := Trim(memoCommit.Text);
  if Msg = '' then
  begin
    if MessageDlg('Git Push', 'Commit message is empty.' + LineEnding + LineEnding +
      'Would you like to Push already-committed local changes to GitHub?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      btnPushClick(Sender);
      Exit;
    end
    else
      Exit;
  end;

  if FGitRunner.Commit(Msg) then
  begin
    LogMessage('Commit successful: ' + Msg);
    memoCommit.Clear;
    CurBranch := FGitRunner.GetCurrentBranch;
    if CurBranch = '' then CurBranch := 'main';
    LogMessage('Pushing branch "' + CurBranch + '" to GitHub...');
    PushOutput := FGitRunner.Push('origin', CurBranch);
    LogMessage('Git push: ' + PushOutput);
    if (Pos('fatal:', LowerCase(PushOutput)) > 0) or (Pos('error:', LowerCase(PushOutput)) > 0) then
      MessageDlg('Git Push Error', PushOutput, mtError, [mbOK], 0)
    else
      MessageDlg('Git Commit & Push', 'Commit and Push completed successfully!' + LineEnding + LineEnding + PushOutput, mtInformation, [mbOK], 0);
    RefreshStatus;
  end
  else
  begin
    LogMessage('Commit failed: ' + FGitRunner.LastError);
    MessageDlg('Git Commit Error', FGitRunner.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TLazGitDockViewForm.btnPullClick(Sender: TObject);
var
  PullOutput, CurBranch: string;
begin
  if not FGitRunner.HasActiveProject then
  begin
    MessageDlg('Git Pull', 'No active project open in Lazarus IDE.', mtWarning, [mbOK], 0);
    Exit;
  end;

  CurBranch := FGitRunner.GetCurrentBranch;
  if CurBranch = '' then CurBranch := 'main';

  LogMessage('Pulling changes from remote origin (' + CurBranch + ')...');
  PullOutput := FGitRunner.Pull('origin', CurBranch);
  LogMessage('Git pull: ' + PullOutput);

  if (Pos('fatal:', LowerCase(PullOutput)) > 0) or (Pos('error:', LowerCase(PullOutput)) > 0) then
    MessageDlg('Git Pull Error', PullOutput, mtError, [mbOK], 0)
  else
    MessageDlg('Git Pull', 'Pull completed successfully!' + LineEnding + LineEnding + PullOutput, mtInformation, [mbOK], 0);

  RefreshStatus;
end;

procedure TLazGitDockViewForm.btnPushClick(Sender: TObject);
var
  PushOutput, CurBranch: string;
begin
  if not FGitRunner.HasActiveProject then
  begin
    MessageDlg('Git Push', 'No active project open in Lazarus IDE.', mtWarning, [mbOK], 0);
    Exit;
  end;

  CurBranch := FGitRunner.GetCurrentBranch;
  if CurBranch = '' then CurBranch := 'main';

  LogMessage('Pushing branch "' + CurBranch + '" to GitHub origin...');
  PushOutput := FGitRunner.Push('origin', CurBranch);
  LogMessage('Git push: ' + PushOutput);

  if (Pos('fatal:', LowerCase(PushOutput)) > 0) or (Pos('error:', LowerCase(PushOutput)) > 0) then
    MessageDlg('Git Push Error', PushOutput, mtError, [mbOK], 0)
  else
    MessageDlg('Git Push', 'Push completed successfully!' + LineEnding + LineEnding + PushOutput, mtInformation, [mbOK], 0);

  RefreshStatus;
end;

procedure TLazGitDockViewForm.btnRevertClick(Sender: TObject);
var
  ActionLog: string;
begin
  if not FGitRunner.HasActiveProject then
  begin
    MessageDlg('Git Revert', 'Nenhum projeto ativo carregado na IDE.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if not FGitRunner.IsRepoInitialized then
  begin
    MessageDlg('Git Revert', 'Este projeto ainda não possui commits ou repositório Git.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if TLazGitRevertForm.Execute(FGitRunner, ActionLog) then
  begin
    LogMessage(ActionLog);
    RefreshStatus;
  end;
end;

procedure TLazGitDockViewForm.btnStageAllClick(Sender: TObject);
begin
  if FGitRunner.StageAll then
  begin
    LogMessage('Staged all changes.');
    RefreshStatus;
  end
  else
    LogMessage('Stage All failed: ' + FGitRunner.LastError);
end;

procedure TLazGitDockViewForm.btnUnstageAllClick(Sender: TObject);
begin
  if FGitRunner.UnstageAll then
  begin
    LogMessage('Unstaged all changes.');
    RefreshStatus;
  end
  else
    LogMessage('Unstage All failed: ' + FGitRunner.LastError);
end;

procedure TLazGitDockViewForm.btnDiffClick(Sender: TObject);
var
  FilePath, DiffText: string;
  IsStaged, IsUntracked: Boolean;
begin
  FilePath := GetSelectedFilePath(IsStaged, IsUntracked);
  if FilePath = '' then
  begin
    MessageDlg('Diff', 'Please select a file from the changes list to view its diff.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if IsUntracked then
  begin
    MessageDlg('Diff', 'Selected file is untracked. No Git diff available until it is staged.', mtInformation, [mbOK], 0);
    Exit;
  end;

  DiffText := FGitRunner.GetDiff(FilePath, IsStaged);
  if DiffText <> '' then
  begin
    LogMessage(Format('--- Diff for %s (%s) ---', [FilePath, BoolToStr(IsStaged, 'Staged', 'Working tree')]));
    LogMessage(DiffText);
  end
  else
    LogMessage('No difference found for ' + FilePath);
end;

procedure TLazGitDockViewForm.btnDiscardClick(Sender: TObject);
var
  FilePath: string;
  IsStaged, IsUntracked: Boolean;
begin
  FilePath := GetSelectedFilePath(IsStaged, IsUntracked);
  if FilePath = '' then
  begin
    MessageDlg('Discard Changes', 'Please select a file from the list to discard changes.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if MessageDlg('Confirm Discard',
    'Are you sure you want to discard changes in "' + FilePath + '"?' + LineEnding +
    'This operation cannot be undone.', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  if FGitRunner.DiscardFile(FilePath, IsUntracked) then
  begin
    LogMessage('Discarded changes for ' + FilePath);
    RefreshStatus;
  end
  else
    LogMessage('Discard failed: ' + FGitRunner.LastError);
end;

procedure TLazGitDockViewForm.lvChangesItemChecked(Sender: TObject; Item: TListItem);
var
  FilePath: string;
begin
  if FUpdatingList or (Item = nil) or (Item.SubItems.Count < 2) then Exit;

  FilePath := Item.SubItems[1];
  if Item.Checked then
  begin
    if FGitRunner.StageFile(FilePath) then
      LogMessage('Staged: ' + FilePath)
    else
      LogMessage('Failed to stage ' + FilePath + ': ' + FGitRunner.LastError);
  end
  else
  begin
    if FGitRunner.UnstageFile(FilePath) then
      LogMessage('Unstaged: ' + FilePath)
    else
      LogMessage('Failed to unstage ' + FilePath + ': ' + FGitRunner.LastError);
  end;

  RefreshStatus;
end;

procedure TLazGitDockViewForm.miStageClick(Sender: TObject);
var
  FilePath: string;
  IsStaged, IsUntracked: Boolean;
begin
  FilePath := GetSelectedFilePath(IsStaged, IsUntracked);
  if FilePath <> '' then
  begin
    if FGitRunner.StageFile(FilePath) then
    begin
      LogMessage('Staged: ' + FilePath);
      RefreshStatus;
    end
    else
      LogMessage('Stage failed: ' + FGitRunner.LastError);
  end;
end;

procedure TLazGitDockViewForm.miUnstageClick(Sender: TObject);
var
  FilePath: string;
  IsStaged, IsUntracked: Boolean;
begin
  FilePath := GetSelectedFilePath(IsStaged, IsUntracked);
  if FilePath <> '' then
  begin
    if FGitRunner.UnstageFile(FilePath) then
    begin
      LogMessage('Unstaged: ' + FilePath);
      RefreshStatus;
    end
    else
      LogMessage('Unstage failed: ' + FGitRunner.LastError);
  end;
end;

procedure TLazGitDockViewForm.miDiffClick(Sender: TObject);
begin
  btnDiffClick(Sender);
end;

procedure TLazGitDockViewForm.miDiscardClick(Sender: TObject);
begin
  btnDiscardClick(Sender);
end;

procedure TLazGitDockViewForm.miStageAllClick(Sender: TObject);
begin
  btnStageAllClick(Sender);
end;

procedure TLazGitDockViewForm.miUnstageAllClick(Sender: TObject);
begin
  btnUnstageAllClick(Sender);
end;

procedure TLazGitDockViewForm.btnConnectGitHubClick(Sender: TObject);
var
  RepoList: TStringList;
  I: Integer;
begin
  GitHubConfig.LoadConfig;
  FGitHubClient.Token := GitHubConfig.GitHubToken;

  if Trim(FGitHubClient.Token) = '' then
  begin
    lblGitHubUser.Caption := 'Disconnected (No PAT)';
    MessageDlg('GitHub Authentication',
      'GitHub Personal Access Token is empty.' + LineEnding +
      'Please click "Settings" or go to Tools > Options > Version Control to enter your PAT.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  LogMessage('Authenticating with GitHub REST API...');
  if FGitHubClient.TestAuthentication then
  begin
    GitHubConfig.GitHubUser := FGitHubClient.AuthenticatedUser;
    GitHubConfig.SaveConfig;
    lblGitHubUser.Caption := '@' + FGitHubClient.AuthenticatedUser;
    lblGitHubUser.Font.Color := clGreen;
    LogMessage('Authenticated successfully as ' + FGitHubClient.AuthenticatedUser);

    RepoList := TStringList.Create;
    try
      if FGitHubClient.ListUserRepositories(RepoList) then
      begin
        cbRepos.Items.BeginUpdate;
        try
          for I := 0 to RepoList.Count - 1 do
          begin
            if cbRepos.Items.IndexOf(RepoList[I]) < 0 then
              cbRepos.Items.Add(RepoList[I]);
          end;
        finally
          cbRepos.Items.EndUpdate;
        end;
        LogMessage(Format('Loaded %d repositories from GitHub.', [RepoList.Count]));
      end
      else
        LogMessage('Failed to list repos: ' + FGitHubClient.LastError);
    finally
      RepoList.Free;
    end;
  end
  else
  begin
    GitHubConfig.GitHubUser := '';
    GitHubConfig.SaveConfig;
    lblGitHubUser.Caption := 'Disconnected (Auth Failed)';
    lblGitHubUser.Font.Color := clMaroon;
    LogMessage('GitHub authentication failed: ' + FGitHubClient.LastError);
    MessageDlg('GitHub Error', FGitHubClient.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TLazGitDockViewForm.btnSettingsClick(Sender: TObject);
begin
  if Assigned(LazarusIDE) then
    LazarusIDE.DoOpenIDEOptions(TLazGitHubOptionsFrame);
end;

procedure TLazGitDockViewForm.btnSetRemoteClick(Sender: TObject);
var
  RepoInput, FullURL, ChosenDir: string;
begin
  if not FGitRunner.HasActiveProject then
  begin
    if MessageDlg('Git Remote',
      'No active project open in Lazarus IDE.' + LineEnding + LineEnding +
      'Would you like to select a folder on your computer to link with this GitHub repository?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      ChosenDir := '';
      if SelectDirectory('Select Project Directory', '', ChosenDir) then
      begin
        FGitRunner.ExplicitWorkingDir := ChosenDir;
        RefreshUI;
      end
      else
        Exit;
    end
    else
      Exit;
  end;

  RepoInput := Trim(cbRepos.Text);
  if RepoInput = '' then
  begin
    MessageDlg('Git Remote', 'Please enter or select a repository (e.g. username/repo or full URL) before linking.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if (Pos('https://', RepoInput) = 1) or (Pos('http://', RepoInput) = 1) or (Pos('git@', RepoInput) = 1) then
    FullURL := RepoInput
  else
    FullURL := 'https://github.com/' + RepoInput + '.git';

  if FGitRunner.SetRemoteURL(FullURL, 'origin') then
  begin
    LogMessage('Git remote "origin" set to: ' + FullURL);
    MessageDlg('Git Remote Linked', 'Remote "origin" successfully set to:' + LineEnding + FullURL, mtInformation, [mbOK], 0);
    RefreshStatus;
    AutoDetectRemoteRepo;
  end
  else
  begin
    LogMessage('Failed to set git remote: ' + FGitRunner.LastError);
    MessageDlg('Git Remote Error', FGitRunner.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TLazGitDockViewForm.cbReposChange(Sender: TObject);
begin
  LogMessage('Active remote repository set to: ' + cbRepos.Text);
end;

procedure TLazGitDockViewForm.btnCreateIssueClick(Sender: TObject);
var
  RepoFull, RepoOwner, RepoName, Title, Body: string;
  SlashPos: Integer;
begin
  RepoFull := Trim(cbRepos.Text);
  SlashPos := Pos('/', RepoFull);
  if SlashPos = 0 then
  begin
    MessageDlg('Repository Selection', 'Please select or enter a repository in "owner/repo" format.', mtWarning, [mbOK], 0);
    Exit;
  end;

  RepoOwner := Copy(RepoFull, 1, SlashPos - 1);
  RepoName := Copy(RepoFull, SlashPos + 1, Length(RepoFull));

  Title := Trim(edtIssueTitle.Text);
  if Title = '' then
  begin
    MessageDlg('Issue Creation', 'Please enter an issue title.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Body := memoIssueBody.Text;
  FGitHubClient.Token := GitHubConfig.GitHubToken;

  LogMessage(Format('Creating issue "%s" in %s/%s...', [Title, RepoOwner, RepoName]));
  if FGitHubClient.CreateIssue(RepoOwner, RepoName, Title, Body) then
  begin
    LogMessage('Issue created successfully!');
    MessageDlg('Success', 'GitHub issue created successfully!', mtInformation, [mbOK], 0);
    edtIssueTitle.Clear;
    memoIssueBody.Clear;
  end
  else
  begin
    LogMessage('Create Issue failed: ' + FGitHubClient.LastError);
    MessageDlg('GitHub API Error', FGitHubClient.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TLazGitDockViewForm.btnCreatePRClick(Sender: TObject);
var
  RepoFull, RepoOwner, RepoName, Title, HeadBranch, BaseBranch, Body: string;
  SlashPos: Integer;
begin
  RepoFull := Trim(cbRepos.Text);
  SlashPos := Pos('/', RepoFull);
  if SlashPos = 0 then
  begin
    MessageDlg('Repository Selection', 'Please select or enter a repository in "owner/repo" format.', mtWarning, [mbOK], 0);
    Exit;
  end;

  RepoOwner := Copy(RepoFull, 1, SlashPos - 1);
  RepoName := Copy(RepoFull, SlashPos + 1, Length(RepoFull));

  Title := Trim(edtPRTitle.Text);
  HeadBranch := Trim(edtPRHead.Text);
  BaseBranch := Trim(edtPRBase.Text);
  Body := memoPRBody.Text;

  if Title = '' then
  begin
    MessageDlg('Pull Request Creation', 'Please enter a Pull Request title.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if HeadBranch = '' then
  begin
    MessageDlg('Pull Request Creation', 'Please enter the Head (source) branch.', mtWarning, [mbOK], 0);
    Exit;
  end;

  if BaseBranch = '' then
  begin
    MessageDlg('Pull Request Creation', 'Please enter the Base (target) branch.', mtWarning, [mbOK], 0);
    Exit;
  end;

  FGitHubClient.Token := GitHubConfig.GitHubToken;

  LogMessage(Format('Creating Pull Request "%s" (%s -> %s) in %s/%s...',
    [Title, HeadBranch, BaseBranch, RepoOwner, RepoName]));

  if FGitHubClient.CreatePullRequest(RepoOwner, RepoName, Title, HeadBranch, BaseBranch, Body) then
  begin
    LogMessage('Pull Request created successfully!');
    MessageDlg('Success', 'GitHub Pull Request created successfully!', mtInformation, [mbOK], 0);
    edtPRTitle.Clear;
    memoPRBody.Clear;
  end
  else
  begin
    LogMessage('Create PR failed: ' + FGitHubClient.LastError);
    MessageDlg('GitHub API Error', FGitHubClient.LastError, mtError, [mbOK], 0);
  end;
end;

end.
