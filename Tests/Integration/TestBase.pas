unit TestBase;

interface

uses
  System.SysUtils, System.Classes, System.Net.HttpClient, System.Net.URLClient,
  System.JSON, Data.DB, FireDAC.Comp.Client, FireDAC.Phys.PG, FireDAC.Stan.Def,
  FireDAC.Stan.Async, DUnitX.TestFramework, System.Generics.Collections,
  FireDAC.Stan.Param, FireDAC.DApt;

type
  /// <summary>
  /// Базовый класс для интеграционных тестов.
  /// Предоставляет подключение к тестовой БД и HTTP-клиент для запросов к серверу.
  /// </summary>
  TIntegrationTestBase = class
  strict private
    FDBConnection: TFDConnection;
    FHTTPClient: THTTPClient;
    FServerURL: string;
    FAuthToken: string;
  strict protected
    /// <summary>Подключение к тестовой БД PostgreSQL</summary>
    property DBConnection: TFDConnection read FDBConnection;
    
    /// <summary>HTTP-клиент для запросов к серверу</summary>
    property HTTPClient: THTTPClient read FHTTPClient;
    
    /// <summary>URL сервера (по умолчанию http://localhost:8082)</summary>
    property ServerURL: string read FServerURL;
    
    /// <summary>Токен авторизации (получается через Login)</summary>
    property AuthToken: string read FAuthToken write FAuthToken;
    
    /// <summary>Выполняет POST-запрос к серверу DataSnap</summary>
    function PostToServer(const Endpoint: string; const JSONPayload: string; 
      const UseAuth: Boolean = True): IHTTPResponse;
    
    /// <summary>Выполняет GET-запрос к серверу DataSnap</summary>
    function GetFromServer(const Endpoint: string; 
      const UseAuth: Boolean = True): IHTTPResponse;
    
    /// <summary>Авторизуется на сервере и сохраняет токен</summary>
    procedure LoginAs(const Username, Password: string);
    
    /// <summary>Очищает все тестовые данные в БД</summary>
    procedure CleanupTestData;
    
    /// <summary>Создаёт тестовую сессию в БД и возвращает токен</summary>
    function CreateTestSession(UserID: Int64; ExpiresInHours: Integer = 24): string;
    
    /// <summary>Создаёт просроченную тестовую сессию в БД</summary>
    function CreateExpiredTestSession(UserID: Int64; ExpiredAgoHours: Integer = 1): string;
    
    /// <summary>Возвращает ID тестового пользователя (test_user)</summary>
    function GetTestUserID: Int64;
    
    /// <summary>Возвращает ID второго тестового пользователя (test_user_2)</summary>
    function GetTestUserID2: Int64;
    
    /// <summary>Возвращает количество записей в таблице</summary>
    function GetTableCount(const TableName: string): Integer;
    
    /// <summary>Проверяет, существует ли файл на диске</summary>
    function FileExistsOnDisk(const FilePath: string): Boolean;
    
    /// <summary>Удаляет файл с диска (если существует)</summary>
    procedure DeleteFileFromDisk(const FilePath: string);
  public
    constructor Create;
    destructor Destroy; override;
    
    /// <summary>Настройка перед каждым тестом</summary>
    [Setup]
    procedure Setup;
    
    /// <summary>Очистка после каждого теста</summary>
    [TearDown]
    procedure TearDown;
  end;

implementation

uses
  System.IOUtils, System.DateUtils;

{ TIntegrationTestBase }

constructor TIntegrationTestBase.Create;
begin
  inherited Create;
  
  // URL сервера (HTTP напрямую к DataSnap, без Nginx)
  FServerURL := 'http://localhost:8082';
  
  // Создаём HTTP-клиент
  FHTTPClient := THTTPClient.Create;
  FHTTPClient.ConnectionTimeout := 10000;  // 10 секунд
  FHTTPClient.ResponseTimeout := 30000;    // 30 секунд
end;

destructor TIntegrationTestBase.Destroy;
begin
  FHTTPClient.Free;
  if Assigned(FDBConnection) then
    FDBConnection.Free;
  inherited;
end;

procedure TIntegrationTestBase.Setup;
begin
  // Создаём подключение к тестовой БД
  FDBConnection := TFDConnection.Create(nil);
  FDBConnection.Params.Clear;
  FDBConnection.Params.DriverID := 'PG';
  FDBConnection.Params.Database := 'audit_test';
  FDBConnection.Params.UserName := 'test_user';
  FDBConnection.Params.Password := 'test_password';
  FDBConnection.Params.Add('Server=localhost');
  FDBConnection.Params.Add('Port=5433');
  FDBConnection.Params.Add('CharacterSet=UTF8');
  
  // Подключаемся к БД
  try
    FDBConnection.Connected := True;
  except
    on E: Exception do
      raise Exception.CreateFmt(
        'Не удалось подключиться к тестовой БД. ' +
        'Убедитесь, что Docker-контейнер запущен (docker-compose -f docker-compose.test.yml up -d). ' +
        'Ошибка: %s', [E.Message]);
  end;
  
  // Очищаем тестовые данные перед каждым тестом
  CleanupTestData;
  
  // Сбрасываем токен
  FAuthToken := '';
end;

procedure TIntegrationTestBase.TearDown;
begin
  // Очищаем тестовые данные после каждого теста
  try
    if Assigned(FDBConnection) and FDBConnection.Connected then
      CleanupTestData;
  except
    // Игнорируем ошибки очистки
  end;
  
  // Отключаемся от БД
  if Assigned(FDBConnection) then
  begin
    FDBConnection.Connected := False;
    FreeAndNil(FDBConnection);
  end;
end;

function TIntegrationTestBase.PostToServer(const Endpoint: string; 
  const JSONPayload: string; const UseAuth: Boolean): IHTTPResponse;
var
  PayloadStream: TStringStream;
  Headers: TNetHeaders;
  FullURL: string;
  HeaderCount: Integer;
begin
  FullURL := FServerURL + Endpoint;
  
  // 🔑 ИСПРАВЛЕНИЕ: Формируем заголовки динамически
  // Windows HTTP API не принимает пустые значения заголовков (ошибка 12150)
  // Поэтому добавляем X-Session-Token только если токен непустой
  HeaderCount := 1; // Content-Type всегда нужен
  if UseAuth and (FAuthToken <> '') then
    Inc(HeaderCount); // Добавляем X-Session-Token
  
  SetLength(Headers, HeaderCount);
  Headers[0].Name := 'Content-Type';
  Headers[0].Value := 'application/json';
  
  if UseAuth and (FAuthToken <> '') then
  begin
    Headers[1].Name := 'X-Session-Token';
    Headers[1].Value := FAuthToken;
  end;
  
  // Создаём поток с JSON
  PayloadStream := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    // 🔑 DataSnap REST ожидает Content-Type: application/json для JSON body
    FHTTPClient.CustomHeaders['Content-Type'] := 'application/json';
    Result := FHTTPClient.Post(FullURL, PayloadStream, nil, Headers);
    FHTTPClient.CustomHeaders['Content-Type'] := '';
  finally
    PayloadStream.Free;
  end;
end;

function TIntegrationTestBase.GetFromServer(const Endpoint: string; 
  const UseAuth: Boolean): IHTTPResponse;
var
  Headers: TNetHeaders;
  FullURL: string;
  HeaderCount: Integer;
begin
  FullURL := FServerURL + Endpoint;
  
  // 🔑 ИСПРАВЛЕНИЕ: Формируем заголовки динамически
  HeaderCount := 0;
  if UseAuth and (FAuthToken <> '') then
    HeaderCount := 1;
  
  SetLength(Headers, HeaderCount);
  if UseAuth and (FAuthToken <> '') then
  begin
    Headers[0].Name := 'X-Session-Token';
    Headers[0].Value := FAuthToken;
  end;
  
  Result := FHTTPClient.Get(FullURL, nil, Headers);
end;

procedure TIntegrationTestBase.LoginAs(const Username, Password: string);
var
  Response: IHTTPResponse;
  JSONPayload: string;
  JSONResp: TJSONObject;
  ResultArr: TJSONArray;
begin
  // 🔑 DataSnap REST для примитивных параметров ожидает JSON body в POST
  JSONPayload := Format('{"AUsername":"%s","APassword":"%s"}', [Username, Password]);
  
  Response := PostToServer('/datasnap/rest/TServerMethods1/updateLogin', JSONPayload, False);
  
  if Response.StatusCode <> 200 then
    raise Exception.CreateFmt('Login failed: HTTP %d - %s', 
      [Response.StatusCode, Response.StatusText]);
  
  // Парсим ответ
  JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    if not Assigned(JSONResp) then
      raise Exception.Create('Login failed: invalid JSON response');
    
    ResultArr := JSONResp.GetValue('result') as TJSONArray;
    if not Assigned(ResultArr) or (ResultArr.Count = 0) then
      raise Exception.Create('Login failed: no token in response');
    
    var InnerObj := ResultArr.Items[0] as TJSONObject;
    if not Assigned(InnerObj) then
      raise Exception.Create('Login failed: inner response not JSON');
    
    var TokenVal := InnerObj.GetValue('token');
    if not Assigned(TokenVal) then
      raise Exception.Create('Login failed: no token field');
    
    FAuthToken := TokenVal.Value;
    
    if FAuthToken = '' then
      raise Exception.Create('Login failed: empty token');
  finally
    JSONResp.Free;
  end;
end;

procedure TIntegrationTestBase.CleanupTestData;
const
  // 🔑 ИСПРАВЛЕНИЕ: Очищаем ВСЕ таблицы, которые использует сервер
  // Порядок важен: сначала дочерние (audit_files), потом родительские (audit_logs, events)
  del_sql: array[0..3] of string = ('audit_files', 'audit_logs', 'events', 'user_sessions');
var
  i: integer;
  Qry: TFDQuery;
begin
  if not Assigned(FDBConnection) or not FDBConnection.Connected then
    Exit;
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    
    for i := Low(del_sql) to High(del_sql) do
    begin
      Qry.SQL.Text := 'DELETE FROM ' + del_sql[i];
      Qry.ExecSQL;
    end;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.CreateTestSession(UserID: Int64; 
  ExpiresInHours: Integer): string;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'SELECT create_test_session(:user_id, make_interval(hours => :hours))';
    Qry.ParamByName('user_id').AsLargeInt := UserID;
    Qry.ParamByName('hours').AsInteger := ExpiresInHours;
    Qry.Open;
    
    if not Qry.IsEmpty then
      Result := Qry.Fields[0].AsString
    else
      raise Exception.Create('Failed to create test session');
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.CreateExpiredTestSession(UserID: Int64; 
  ExpiredAgoHours: Integer): string;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'SELECT create_expired_test_session(:user_id, make_interval(hours => :hours))';
    Qry.ParamByName('user_id').AsLargeInt := UserID;
    Qry.ParamByName('hours').AsInteger := ExpiredAgoHours;
    Qry.Open;
    
    if not Qry.IsEmpty then
      Result := Qry.Fields[0].AsString
    else
      raise Exception.Create('Failed to create expired test session');
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.GetTestUserID: Int64;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 'SELECT id FROM users WHERE username = ''test_user'' AND is_active = TRUE LIMIT 1';
    Qry.Open;

    if not Qry.IsEmpty then
      Result := Qry.Fields[0].AsLargeInt
    else
      raise Exception.Create('Test user "test_user" not found in database. Run init-test-db.sql first.');

    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.GetTestUserID2: Int64;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 'SELECT id FROM users WHERE username = ''test_user_2'' AND is_active = TRUE LIMIT 1';
    Qry.Open;

    if not Qry.IsEmpty then
      Result := Qry.Fields[0].AsLargeInt
    else
      raise Exception.Create('Test user "test_user_2" not found in database. Run init-test-db.sql first.');

    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.GetTableCount(const TableName: string): Integer;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    // 🔑 ИСПРАВЛЕНИЕ: Используем имена таблиц без суффикса _test
    Qry.SQL.Text := Format('SELECT COUNT(*) FROM %s', [TableName]);
    Qry.Open;
    
    if not Qry.IsEmpty then
      Result := Qry.Fields[0].AsInteger
    else
      Result := 0;
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TIntegrationTestBase.FileExistsOnDisk(const FilePath: string): Boolean;
begin
  // Путь на сервере (C:\AuditFiles\...)
  Result := TFile.Exists(FilePath);
end;

procedure TIntegrationTestBase.DeleteFileFromDisk(const FilePath: string);
begin
  if TFile.Exists(FilePath) then
    TFile.Delete(FilePath);
end;

end.
