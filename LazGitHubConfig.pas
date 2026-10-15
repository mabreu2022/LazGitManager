unit LazGitHubConfig;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  // IDEIntf & LazUtils
  LazConfigStorage, BaseIDEIntf, LazIDEIntf, XMLConf;

const
  DefaultGitExecutable = 'git';
  DefaultAutoFetchInterval = 0; // 0 = disabled
  ConfigFileName = 'lazgithub.xml';

type
  { TLazGitHubConfig }

  TLazGitHubConfig = class
  private
    FGitHubToken: string;
    FGitHubUser: string;
    FGitExecutablePath: string;
    FAutoFetchInterval: Integer;
    FOnChange: TNotifyEvent;
    function GetFallbackConfigFile: string;
    procedure DoChanged;
  public
    constructor Create;
    destructor Destroy; override;

    procedure LoadConfig;
    procedure SaveConfig;

    property GitHubToken: string read FGitHubToken write FGitHubToken;
    property GitHubUser: string read FGitHubUser write FGitHubUser;
    property GitExecutablePath: string read FGitExecutablePath write FGitExecutablePath;
    property AutoFetchInterval: Integer read FAutoFetchInterval write FAutoFetchInterval;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

function GitHubConfig: TLazGitHubConfig;

implementation

var
  FGlobalConfig: TLazGitHubConfig = nil;

function GitHubConfig: TLazGitHubConfig;
begin
  if FGlobalConfig = nil then
  begin
    FGlobalConfig := TLazGitHubConfig.Create;
    FGlobalConfig.LoadConfig;
  end;
  Result := FGlobalConfig;
end;

{ TLazGitHubConfig }

constructor TLazGitHubConfig.Create;
begin
  inherited Create;
  FGitExecutablePath := DefaultGitExecutable;
  FAutoFetchInterval := DefaultAutoFetchInterval;
  FGitHubToken := '';
  FGitHubUser := '';
end;

destructor TLazGitHubConfig.Destroy;
begin
  inherited Destroy;
end;

procedure TLazGitHubConfig.DoChanged;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TLazGitHubConfig.GetFallbackConfigFile: string;
var
  Dir: string;
begin
  if Assigned(LazarusIDE) then
    Dir := LazarusIDE.GetPrimaryConfigPath
  else
    Dir := GetAppConfigDir(False);

  if (Dir <> '') and not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  Result := IncludeTrailingPathDelimiter(Dir) + ConfigFileName;
end;

procedure TLazGitHubConfig.LoadConfig;
var
  Storage: TConfigStorage;
  Xml: TXMLConfig;
  CfgPath: string;
begin
  // Primary attempt: Use standard IDE storage handler if available
  if Assigned(GetIDEConfigStorage) then
  begin
    try
      Storage := GetIDEConfigStorage(ConfigFileName, True);
      try
        FGitHubToken := Storage.GetValue('GitHub/Token/Value', '');
        FGitHubUser := Storage.GetValue('GitHub/User/Value', '');
        FGitExecutablePath := Storage.GetValue('Git/ExecutablePath/Value', DefaultGitExecutable);
        FAutoFetchInterval := Storage.GetValue('Git/AutoFetchInterval/Value', DefaultAutoFetchInterval);
        Exit;
      finally
        Storage.Free;
      end;
    except
      on E: Exception do
        // Storage might fail if file does not exist yet; fall back to TXMLConfig
    end;
  end;

  // Secondary fallback: Direct TXMLConfig in Lazarus primary config path
  CfgPath := GetFallbackConfigFile;
  if FileExists(CfgPath) then
  begin
    Xml := TXMLConfig.Create(nil);
    try
      try
        Xml.Filename := CfgPath;
        FGitHubToken := Xml.GetValue('GitHub/Token/Value', '');
        FGitHubUser := Xml.GetValue('GitHub/User/Value', '');
        FGitExecutablePath := Xml.GetValue('Git/ExecutablePath/Value', DefaultGitExecutable);
        FAutoFetchInterval := Xml.GetValue('Git/AutoFetchInterval/Value', DefaultAutoFetchInterval);
      except
        // Ignore read errors, keep defaults
      end;
    finally
      Xml.Free;
    end;
  end;
end;

procedure TLazGitHubConfig.SaveConfig;
var
  Storage: TConfigStorage;
  Xml: TXMLConfig;
  CfgPath: string;
begin
  // Primary attempt: Use standard IDE storage handler if available
  if Assigned(GetIDEConfigStorage) then
  begin
    try
      Storage := GetIDEConfigStorage(ConfigFileName, False);
      try
        Storage.SetDeleteValue('GitHub/Token/Value', FGitHubToken, '');
        Storage.SetDeleteValue('GitHub/User/Value', FGitHubUser, '');
        Storage.SetDeleteValue('Git/ExecutablePath/Value', FGitExecutablePath, DefaultGitExecutable);
        Storage.SetDeleteValue('Git/AutoFetchInterval/Value', FAutoFetchInterval, DefaultAutoFetchInterval);
      finally
        Storage.Free;
      end;
      DoChanged;
      Exit;
    except
      on E: Exception do
        // Fall back to direct XML saving
    end;
  end;

  // Secondary fallback: Direct TXMLConfig in Lazarus primary config path
  CfgPath := GetFallbackConfigFile;
  Xml := TXMLConfig.Create(nil);
  try
    try
      Xml.Filename := CfgPath;
      Xml.SetValue('GitHub/Token/Value', FGitHubToken);
      Xml.SetValue('GitHub/User/Value', FGitHubUser);
      Xml.SetValue('Git/ExecutablePath/Value', FGitExecutablePath);
      Xml.SetValue('Git/AutoFetchInterval/Value', FAutoFetchInterval);
      Xml.Flush;
    except
      on E: Exception do
        // Suppress or log file write issues
    end;
  finally
    Xml.Free;
  end;
  DoChanged;
end;

initialization

finalization
  FreeAndNil(FGlobalConfig);

end.
