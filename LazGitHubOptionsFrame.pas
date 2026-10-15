unit LazGitHubOptionsFrame;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Spin,
  // IDEIntf
  IDEOptionsIntf, IDEOptEditorIntf,
  // Local units
  LazGitHubConfig, LazGitHubAPI;

type
  { TLazGitHubOptionsFrame }

  TLazGitHubOptionsFrame = class(TAbstractIDEOptionsEditor)
    gbGit: TGroupBox;
    lblGitPath: TLabel;
    edtGitPath: TEdit;
    btnBrowseGit: TButton;
    lblAutoFetch: TLabel;
    seAutoFetch: TSpinEdit;
    lblAutoFetchHint: TLabel;
    OpenDialogGit: TOpenDialog;

    gbGitHub: TGroupBox;
    lblToken: TLabel;
    edtToken: TEdit;
    btnTogglePassword: TButton;
    btnTestConnection: TButton;
    lblStatus: TLabel;
    lblTokenHelp: TLabel;

    procedure btnBrowseGitClick(Sender: TObject);
    procedure btnTogglePasswordClick(Sender: TObject);
    procedure btnTestConnectionClick(Sender: TObject);
  public
    function GetTitle: String; override;
    procedure Setup(ADialog: TAbstractOptionsEditorDialog); override;
    procedure ReadSettings(AOptions: TAbstractIDEOptions); override;
    procedure WriteSettings(AOptions: TAbstractIDEOptions); override;
    class function SupportedOptionsClass: TAbstractIDEOptionsClass; override;
  end;

implementation

{$R *.lfm}

{ TLazGitHubOptionsFrame }

function TLazGitHubOptionsFrame.GetTitle: String;
begin
  Result := 'GitHub Integration';
end;

procedure TLazGitHubOptionsFrame.Setup(ADialog: TAbstractOptionsEditorDialog);
begin
  // Set up dialog hints or translation if needed
end;

procedure TLazGitHubOptionsFrame.ReadSettings(AOptions: TAbstractIDEOptions);
begin
  GitHubConfig.LoadConfig;
  edtGitPath.Text := GitHubConfig.GitExecutablePath;
  edtToken.Text := GitHubConfig.GitHubToken;
  seAutoFetch.Value := GitHubConfig.AutoFetchInterval;
  lblStatus.Caption := '';
end;

procedure TLazGitHubOptionsFrame.WriteSettings(AOptions: TAbstractIDEOptions);
begin
  GitHubConfig.GitExecutablePath := Trim(edtGitPath.Text);
  GitHubConfig.GitHubToken := Trim(edtToken.Text);
  GitHubConfig.AutoFetchInterval := seAutoFetch.Value;
  if GitHubConfig.GitHubToken = '' then
    GitHubConfig.GitHubUser := '';
  GitHubConfig.SaveConfig;
end;

class function TLazGitHubOptionsFrame.SupportedOptionsClass: TAbstractIDEOptionsClass;
begin
  Result := IDEEditorGroups.GetByIndex(GroupEnvironment)^.GroupClass;
end;

procedure TLazGitHubOptionsFrame.btnBrowseGitClick(Sender: TObject);
begin
  OpenDialogGit.InitialDir := ExtractFileDir(edtGitPath.Text);
  if OpenDialogGit.Execute then
    edtGitPath.Text := OpenDialogGit.FileName;
end;

procedure TLazGitHubOptionsFrame.btnTogglePasswordClick(Sender: TObject);
begin
  if edtToken.EchoMode = emPassword then
  begin
    edtToken.EchoMode := emNormal;
    btnTogglePassword.Caption := 'Hide';
  end
  else
  begin
    edtToken.EchoMode := emPassword;
    btnTogglePassword.Caption := 'Show';
  end;
end;

procedure TLazGitHubOptionsFrame.btnTestConnectionClick(Sender: TObject);
var
  Client: TLazGitHubClient;
  RawToken: string;
begin
  RawToken := Trim(edtToken.Text);
  if RawToken = '' then
  begin
    lblStatus.Font.Color := clRed;
    lblStatus.Caption := 'Please enter a GitHub Personal Access Token first.';
    Exit;
  end;

  lblStatus.Font.Color := clWindowText;
  lblStatus.Caption := 'Connecting to GitHub REST API...';
  Application.ProcessMessages;

  Client := TLazGitHubClient.Create;
  try
    Client.Token := RawToken;
    if Client.TestAuthentication then
    begin
      lblStatus.Font.Color := clGreen;
      lblStatus.Caption := 'Success! Authenticated as @' + Client.AuthenticatedUser;
      GitHubConfig.GitHubUser := Client.AuthenticatedUser;
    end
    else
    begin
      lblStatus.Font.Color := clRed;
      lblStatus.Caption := 'Failed: ' + Client.LastError;
    end;
  finally
    Client.Free;
  end;
end;

end.
