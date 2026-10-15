unit LazGitHubRegistration;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LCLType, Controls, Forms, Dialogs,
  // IDEIntf
  MenuIntf, IDECommands, IDEWindowIntf, IDEOptionsIntf, IDEOptEditorIntf, LazIDEIntf,
  // Plugin units
  LazGitHubConfig, LazGitDockForm, LazGitHubOptionsFrame;

procedure Register;

implementation

const
  OptionsEditorGitHubIndex = 1500;

procedure OnShowGitDockForm(Sender: TObject);
begin
  ShowLazGitDockForm;
end;

procedure OnCommitActiveProject(Sender: TObject);
begin
  if not Assigned(LazarusIDE) or not Assigned(LazarusIDE.ActiveProject) or
     (LazarusIDE.ActiveProject.ProjectInfoFile = '') then
  begin
    MessageDlg('Git Integration',
      'No active project is currently loaded in Lazarus IDE.' + LineEnding +
      'Please open a project with a Git repository first.',
      mtInformation, [mbOK], 0);
    Exit;
  end;

  ShowLazGitDockForm;

  if Assigned(LazGitDockViewFormInstance) then
  begin
    LazGitDockViewFormInstance.PageControl.ActivePageIndex := 0;
    if LazGitDockViewFormInstance.memoCommit.CanFocus then
      LazGitDockViewFormInstance.memoCommit.SetFocus;
  end;
end;

procedure Register;
var
  ViewCat: TIDECommandCategory;
  CmdViewGit: TIDECommand;
begin
  // 1. Register dockable window creator in Lazarus IDEWindowCreators
  IDEWindowCreators.Add(
    LazGitDockFormName,
    @CreateLazGitDockViewForm,
    nil,
    '150', '150', '800', '600',
    '', alNone, False
  );

  // 2. Register IDE Command with Ctrl+Shift+G shortcut (VS Code standard)
  ViewCat := IDECommandList.FindCategoryByName(CommandCategoryViewName);
  if ViewCat = nil then
    ViewCat := RegisterIDECommandCategory(nil, 'GitCommands', 'Git & GitHub Commands');

  CmdViewGit := RegisterIDECommand(
    ViewCat,
    'ViewGitGitHubManager',
    'Git && GitHub Manager',
    IDEShortCut(VK_G, [ssCtrl, ssShift]),
    nil,
    @OnShowGitDockForm
  );

  // 3. Inject menu items into Lazarus main menus
  // Under View > Main Windows
  RegisterIDEMenuCommand(
    itmViewMainWindows,
    'LazGitManagerMenuItem',
    'Git && GitHub Manager',
    nil,
    @OnShowGitDockForm,
    CmdViewGit
  );

  // Under Project > Project Save Section
  RegisterIDEMenuCommand(
    itmProjectSaveSection,
    'LazGitCommitProjectMenuItem',
    'Git Commit Active Project...',
    nil,
    @OnCommitActiveProject,
    nil
  );

  // 4. Register the Options Frame into IDE Options dialog under "Ambiente / Environment"
  RegisterIDEOptionsEditor(GroupEnvironment, TLazGitHubOptionsFrame, OptionsEditorGitHubIndex);
end;

end.
