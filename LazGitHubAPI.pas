unit LazGitHubAPI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  // FCL Networking & JSON
  fphttpclient, opensslsockets, fpjson, jsonparser, jsonscanner;

const
  GitHubApiBaseURL = 'https://api.github.com';
  GitHubApiVersion = '2022-11-28';
  GitHubUserAgent  = 'LazGitHub-Plugin';

type
  { TLazGitHubClient }

  TLazGitHubClient = class
  private
    FToken: string;
    FAuthenticatedUser: string;
    FLastError: string;
    FLastStatusCode: Integer;

    procedure SetupHeaders(AClient: TFPHTTPClient);
    function ExecuteRequest(const AMethod, AURL, APayload: string; out AResponse: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function TestAuthentication: Boolean;
    function GetUserProfile: TJSONObject;
    function ListUserRepositories(out AList: TStringList): Boolean;
    function CreateIssue(const ARepoOwner, ARepoName, ATitle, ABody: string): Boolean;
    function CreatePullRequest(const ARepoOwner, ARepoName, ATitle, AHead, ABase, ABody: string): Boolean;

    property Token: string read FToken write FToken;
    property AuthenticatedUser: string read FAuthenticatedUser;
    property LastError: string read FLastError;
    property LastStatusCode: Integer read FLastStatusCode;
  end;

implementation

{ TLazGitHubClient }

constructor TLazGitHubClient.Create;
begin
  inherited Create;
  FToken := '';
  FAuthenticatedUser := '';
  FLastError := '';
  FLastStatusCode := 0;
end;

destructor TLazGitHubClient.Destroy;
begin
  inherited Destroy;
end;

procedure TLazGitHubClient.SetupHeaders(AClient: TFPHTTPClient);
begin
  AClient.AllowRedirect := True;
  AClient.AddHeader('Accept', 'application/vnd.github+json');
  AClient.AddHeader('X-GitHub-Api-Version', GitHubApiVersion);
  AClient.AddHeader('User-Agent', GitHubUserAgent);
  if FToken <> '' then
    AClient.AddHeader('Authorization', 'Bearer ' + FToken);
end;

function TLazGitHubClient.ExecuteRequest(const AMethod, AURL, APayload: string; out AResponse: string): Boolean;
var
  Client: TFPHTTPClient;
  ReqStream: TStringStream;
  RespStream: TStringStream;
  Parser: TJSONParser;
  ErrData: TJSONData;
  ErrObj: TJSONObject;
begin
  Result := False;
  AResponse := '';
  FLastError := '';
  FLastStatusCode := 0;

  if (FToken = '') and (AMethod <> 'GET') then
  begin
    FLastError := 'GitHub Personal Access Token (PAT) is empty. Please configure it in Tools > Options > Version Control.';
    Exit;
  end;

  Client := TFPHTTPClient.Create(nil);
  RespStream := TStringStream.Create('');
  ReqStream := nil;
  try
    try
      SetupHeaders(Client);

      if APayload <> '' then
      begin
        Client.AddHeader('Content-Type', 'application/json; charset=utf-8');
        ReqStream := TStringStream.Create(APayload);
        Client.RequestBody := ReqStream;
      end;

      // Allow 200, 201, 202, 204 and common error status codes so we can parse response payloads
      Client.HTTPMethod(AMethod, AURL, RespStream, [200, 201, 202, 204, 400, 401, 403, 404, 422]);
      FLastStatusCode := Client.ResponseStatusCode;
      AResponse := RespStream.DataString;

      if FLastStatusCode in [200, 201, 202, 204] then
        Result := True
      else
      begin
        // Default error text
        FLastError := Format('HTTP Error %d: %s', [FLastStatusCode, Client.ResponseStatusText]);

        // Attempt to extract GitHub's descriptive error message from the response JSON
        if AResponse <> '' then
        begin
          try
            Parser := TJSONParser.Create(AResponse, [joUTF8]);
            try
              ErrData := Parser.Parse;
              if (ErrData <> nil) and (ErrData is TJSONObject) then
              begin
                ErrObj := TJSONObject(ErrData);
                if ErrObj.Find('message') <> nil then
                  FLastError := Format('GitHub Error (%d): %s', [FLastStatusCode, ErrObj.Get('message', '')]);
              end;
            finally
              FreeAndNil(ErrData);
              Parser.Free;
            end;
          except
            // Keep the default formatted HTTP error message if response is not JSON
          end;
        end;

        // Provide specialized hints for common GitHub API status codes
        case FLastStatusCode of
          401: FLastError := FLastError + ' (Invalid or expired token)';
          403: FLastError := FLastError + ' (Rate limit exceeded or insufficient scope)';
          404: FLastError := FLastError + ' (Resource not found or repository access denied)';
          422: FLastError := FLastError + ' (Validation failed - check branch names or duplicate PR)';
        end;
      end;
    except
      on E: Exception do
      begin
        FLastError := 'HTTPS Connection error: ' + E.Message;
        Result := False;
      end;
    end;
  finally
    Client.RequestBody := nil;
    FreeAndNil(ReqStream);
    RespStream.Free;
    Client.Free;
  end;
end;

function TLazGitHubClient.GetUserProfile: TJSONObject;
var
  Resp: string;
  Parser: TJSONParser;
  Data: TJSONData;
begin
  Result := nil;
  if ExecuteRequest('GET', GitHubApiBaseURL + '/user', '', Resp) then
  begin
    try
      Parser := TJSONParser.Create(Resp, [joUTF8]);
      try
        Data := Parser.Parse;
        if (Data <> nil) and (Data is TJSONObject) then
          Result := TJSONObject(Data)
        else
          FreeAndNil(Data);
      finally
        Parser.Free;
      end;
    except
      on E: Exception do
      begin
        FLastError := 'JSON parse error in GetUserProfile: ' + E.Message;
        Result := nil;
      end;
    end;
  end;
end;

function TLazGitHubClient.TestAuthentication: Boolean;
var
  Profile: TJSONObject;
begin
  Result := False;
  FAuthenticatedUser := '';
  Profile := GetUserProfile;
  if Profile <> nil then
  begin
    try
      FAuthenticatedUser := Profile.Get('login', '');
      Result := (FAuthenticatedUser <> '');
    finally
      Profile.Free;
    end;
  end;
end;

function TLazGitHubClient.ListUserRepositories(out AList: TStringList): Boolean;
var
  Resp: string;
  Parser: TJSONParser;
  Data: TJSONData;
  Arr: TJSONArray;
  I: Integer;
  RepoObj: TJSONObject;
  FullName: string;
begin
  Result := False;
  AList := TStringList.Create;
  if ExecuteRequest('GET', GitHubApiBaseURL + '/user/repos?sort=updated&per_page=30', '', Resp) then
  begin
    try
      Parser := TJSONParser.Create(Resp, [joUTF8]);
      try
        Data := Parser.Parse;
        if (Data <> nil) and (Data is TJSONArray) then
        begin
          Arr := TJSONArray(Data);
          for I := 0 to Arr.Count - 1 do
          begin
            if Arr.Items[I] is TJSONObject then
            begin
              RepoObj := TJSONObject(Arr.Items[I]);
              FullName := RepoObj.Get('full_name', '');
              if FullName <> '' then
                AList.Add(FullName);
            end;
          end;
          Result := True;
        end;
      finally
        FreeAndNil(Data);
        Parser.Free;
      end;
    except
      on E: Exception do
      begin
        FLastError := 'JSON parse error in ListUserRepositories: ' + E.Message;
        Result := False;
      end;
    end;
  end;
end;

function TLazGitHubClient.CreateIssue(const ARepoOwner, ARepoName, ATitle, ABody: string): Boolean;
var
  URL, Payload, Resp: string;
  JsonObj: TJSONObject;
begin
  Result := False;
  if (ARepoOwner = '') or (ARepoName = '') then
  begin
    FLastError := 'Repository Owner and Repository Name must not be empty.';
    Exit;
  end;

  if Trim(ATitle) = '' then
  begin
    FLastError := 'Issue title cannot be empty.';
    Exit;
  end;

  URL := Format('%s/repos/%s/%s/issues', [GitHubApiBaseURL, ARepoOwner, ARepoName]);
  JsonObj := TJSONObject.Create;
  try
    JsonObj.Add('title', ATitle);
    if ABody <> '' then
      JsonObj.Add('body', ABody);
    Payload := JsonObj.AsJSON;
  finally
    JsonObj.Free;
  end;

  Result := ExecuteRequest('POST', URL, Payload, Resp);
end;

function TLazGitHubClient.CreatePullRequest(const ARepoOwner, ARepoName, ATitle, AHead, ABase, ABody: string): Boolean;
var
  URL, Payload, Resp: string;
  JsonObj: TJSONObject;
begin
  Result := False;
  if (ARepoOwner = '') or (ARepoName = '') then
  begin
    FLastError := 'Repository Owner and Repository Name must not be empty.';
    Exit;
  end;

  if Trim(ATitle) = '' then
  begin
    FLastError := 'Pull Request title cannot be empty.';
    Exit;
  end;

  if Trim(AHead) = '' then
  begin
    FLastError := 'Pull Request Head branch cannot be empty.';
    Exit;
  end;

  if Trim(ABase) = '' then
  begin
    FLastError := 'Pull Request Base branch cannot be empty.';
    Exit;
  end;

  URL := Format('%s/repos/%s/%s/pulls', [GitHubApiBaseURL, ARepoOwner, ARepoName]);
  JsonObj := TJSONObject.Create;
  try
    JsonObj.Add('title', ATitle);
    JsonObj.Add('head', AHead);
    JsonObj.Add('base', ABase);
    if ABody <> '' then
      JsonObj.Add('body', ABody);
    Payload := JsonObj.AsJSON;
  finally
    JsonObj.Free;
  end;

  Result := ExecuteRequest('POST', URL, Payload, Resp);
end;

end.
