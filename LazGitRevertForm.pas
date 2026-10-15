unit LazGitRevertForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ComCtrls,
  StdCtrls, ExtCtrls, Buttons,
  LazGitCLI;

type
  { TLazGitRevertForm }

  TLazGitRevertForm = class(TForm)
    PanelTop: TPanel;
    lblPrompt: TLabel;
    lvCommits: TListView;
    PanelBottom: TPanel;
    rgMode: TRadioGroup;
    PanelButtons: TPanel;
    btnConfirm: TButton;
    btnCancel: TButton;
    lblWarning: TLabel;

    procedure FormCreate(Sender: TObject);
    procedure btnConfirmClick(Sender: TObject);
    procedure lvCommitsDblClick(Sender: TObject);
  private
    FGitRunner: TLazGitRunner;
    procedure LoadHistory;
  public
    class function Execute(AGitRunner: TLazGitRunner; out AActionLog: string): Boolean;
  end;

implementation

{$R *.lfm}

{ TLazGitRevertForm }

procedure TLazGitRevertForm.FormCreate(Sender: TObject);
begin
  Position := poScreenCenter;
end;

procedure TLazGitRevertForm.LoadHistory;
var
  HistoryList: TStringList;
  I, Tab1, Tab2, Tab3, Tab4: Integer;
  Line, FullHash, ShortHash, DateStr, Author, Msg: string;
  Item: TListItem;
begin
  if not Assigned(FGitRunner) then Exit;

  HistoryList := TStringList.Create;
  try
    lvCommits.Items.BeginUpdate;
    try
      lvCommits.Items.Clear;
      if FGitRunner.GetCommitHistory(HistoryList, 60) then
      begin
        for I := 0 to HistoryList.Count - 1 do
        begin
          Line := HistoryList[I];
          // Format: %H #9 %h #9 %ad #9 %an #9 %s
          Tab1 := Pos(#9, Line);
          if Tab1 <= 0 then Continue;
          FullHash := Copy(Line, 1, Tab1 - 1);
          Delete(Line, 1, Tab1);

          Tab2 := Pos(#9, Line);
          if Tab2 <= 0 then Continue;
          ShortHash := Copy(Line, 1, Tab2 - 1);
          Delete(Line, 1, Tab2);

          Tab3 := Pos(#9, Line);
          if Tab3 <= 0 then Continue;
          DateStr := Copy(Line, 1, Tab3 - 1);
          Delete(Line, 1, Tab3);

          Tab4 := Pos(#9, Line);
          if Tab4 <= 0 then Continue;
          Author := Copy(Line, 1, Tab4 - 1);
          Delete(Line, 1, Tab4);

          Msg := Line;

          Item := lvCommits.Items.Add;
          Item.Caption := ShortHash;
          Item.SubItems.Add(DateStr);
          Item.SubItems.Add(Author);
          Item.SubItems.Add(Msg);
          Item.SubItems.Add(FullHash); // Hidden 4th subitem holding full hash
        end;

        if lvCommits.Items.Count > 0 then
        begin
          lvCommits.Items[0].Selected := True;
          lvCommits.Items[0].Focused := True;
        end;
      end;
    finally
      lvCommits.Items.EndUpdate;
    end;
  finally
    HistoryList.Free;
  end;
end;

procedure TLazGitRevertForm.btnConfirmClick(Sender: TObject);
var
  Item: TListItem;
  FullHash, ShortHash, CommitMsg, PromptMsg: string;
begin
  Item := lvCommits.Selected;
  if Item = nil then
  begin
    MessageDlg('Seleção de Commit', 'Por favor, selecione um commit na lista acima para reverter.', mtWarning, [mbOK], 0);
    Exit;
  end;

  ShortHash := Item.Caption;
  CommitMsg := Item.SubItems[2];
  FullHash := Item.SubItems[3];

  case rgMode.ItemIndex of
    0: PromptMsg := Format('Atenção: Hard Reset irá descartar quaisquer alterações posteriores e colocar o código exatamente no estado de:' + LineEnding + LineEnding +
                          'Commit: %s' + LineEnding +
                          'Mensagem: "%s"' + LineEnding + LineEnding +
                          'Deseja continuar com o Hard Reset?', [ShortHash, CommitMsg]);
    1: PromptMsg := Format('Soft Reset irá mover o ponteiro para o commit %s, mantendo as alterações posteriores nos seus arquivos locais.' + LineEnding + LineEnding +
                          'Deseja continuar com o Soft Reset?', [ShortHash]);
    2: PromptMsg := Format('Git Revert criará um novo commit desfazendo as alterações inseridas pelo commit %s ("%s").' + LineEnding + LineEnding +
                          'Deseja prosseguir com o Revert?', [ShortHash, CommitMsg]);
  else
    PromptMsg := 'Deseja confirmar esta ação?';
  end;

  if MessageDlg('Confirmação de Reversão', PromptMsg, mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    ModalResult := mrOk;
end;

procedure TLazGitRevertForm.lvCommitsDblClick(Sender: TObject);
begin
  if lvCommits.Selected <> nil then
    btnConfirmClick(Sender);
end;

class function TLazGitRevertForm.Execute(AGitRunner: TLazGitRunner; out AActionLog: string): Boolean;
var
  Form: TLazGitRevertForm;
  Item: TListItem;
  FullHash, ShortHash, CommitMsg: string;
begin
  Result := False;
  AActionLog := '';

  if not Assigned(AGitRunner) or not AGitRunner.HasActiveProject then
  begin
    MessageDlg('Git Revert', 'Nenhum projeto ativo carregado na IDE.', mtWarning, [mbOK], 0);
    Exit;
  end;

  Form := TLazGitRevertForm.Create(nil);
  try
    Form.FGitRunner := AGitRunner;
    Form.LoadHistory;

    if Form.lvCommits.Items.Count = 0 then
    begin
      MessageDlg('Git Revert', 'Nenhum commit encontrado no histórico deste projeto.', mtInformation, [mbOK], 0);
      Exit;
    end;

    if Form.ShowModal = mrOk then
    begin
      Item := Form.lvCommits.Selected;
      if Item <> nil then
      begin
        ShortHash := Item.Caption;
        CommitMsg := Item.SubItems[2];
        FullHash := Item.SubItems[3];

        case Form.rgMode.ItemIndex of
          0: // Hard Reset
          begin
            if AGitRunner.ResetToCommit(FullHash, True) then
            begin
              AActionLog := Format('Hard reset realizado com sucesso para o commit [%s]: %s', [ShortHash, CommitMsg]);
              MessageDlg('Git Reset', AActionLog, mtInformation, [mbOK], 0);
              Result := True;
            end
            else
            begin
              AActionLog := 'Falha no Hard Reset: ' + AGitRunner.LastError;
              MessageDlg('Git Reset Error', AActionLog, mtError, [mbOK], 0);
            end;
          end;

          1: // Soft/Mixed Reset
          begin
            if AGitRunner.ResetToCommit(FullHash, False) then
            begin
              AActionLog := Format('Soft reset realizado com sucesso para o commit [%s]: %s', [ShortHash, CommitMsg]);
              MessageDlg('Git Reset', AActionLog, mtInformation, [mbOK], 0);
              Result := True;
            end
            else
            begin
              AActionLog := 'Falha no Soft Reset: ' + AGitRunner.LastError;
              MessageDlg('Git Reset Error', AActionLog, mtError, [mbOK], 0);
            end;
          end;

          2: // Git Revert
          begin
            if AGitRunner.RevertCommit(FullHash) then
            begin
              AActionLog := Format('Commit revertido com sucesso [%s]: %s', [ShortHash, CommitMsg]);
              MessageDlg('Git Revert', AActionLog, mtInformation, [mbOK], 0);
              Result := True;
            end
            else
            begin
              AActionLog := 'Falha no Git Revert: ' + AGitRunner.LastError;
              MessageDlg('Git Revert Error', AActionLog, mtError, [mbOK], 0);
            end;
          end;
        end;
      end;
    end;
  finally
    Form.Free;
  end;
end;

end.
