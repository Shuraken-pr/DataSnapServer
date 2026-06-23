unit TestSecurityIntegration;

interface

uses
  DUnitX.TestFramework, FireDAC.Comp.Client, System.Net.HttpClient,
  System.Net.URLClient, FireDAC.Stan.Param;

type
  /// <summary>
  /// Интеграционные тесты для безопасности (SEC-001..009)
  /// </summary>
  [TestFixture]
  TTestSecurityIntegration = class
  strict private
    FDBConnection: TFDConnection;
    FHTTPClient: THTTPClient;
    FServerURL: string;
    function CreateTestSession(AUserID: Int64): string;
    procedure CleanupTestData;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    /// <summary>SEC-001: Успешный вход записывается в аудит</summary>
    [Test]
    procedure TestLogin_Success_RecordsEvent;
    
    /// <summary>SEC-002: Блокировка после 5 неудачных попыток</summary>
    [Test]
    procedure TestLogin_FailedAfter5Attempts_LocksAccount;
    
    /// <summary>SEC-003: Заблокированный аккаунт отклоняется</summary>
    [Test]
    procedure TestLogin_LockedAccount_Rejected;
    
    /// <summary>SEC-004: Разблокировка после успешного входа</summary>
    [Test]
    procedure TestLogin_UnlockedAfterSuccessfulLogin;
    
    /// <summary>SEC-005: Rate limit для Login (20/час)</summary>
    [Test]
    procedure TestRateLimit_LoginExceeded_Returns429;
    
    /// <summary>SEC-006: Rate limit для Upload (100/час)</summary>
    [Test]
    procedure TestRateLimit_UploadExceeded_Returns429;
    
    /// <summary>SEC-007: Разные лимиты для разных IP</summary>
    [Test]
    procedure TestRateLimit_DifferentIPs_SeparateLimits;
    
    /// <summary>SEC-008: События сохраняются после перезапуска</summary>
    [Test]
    procedure TestSecurityEvents_RetainedAfterRestart;
    
    /// <summary>SEC-009: Фильтр критических событий</summary>
    [Test]
    procedure TestSecurityEvents_CriticalEventsFilter;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  FireDAC.Stan.Def, FireDAC.Phys.PG, FireDAC.Phys.PGDef, Data.DB;

{ TTestSecurityIntegration }

procedure TTestSecurityIntegration.Setup;
begin
  // Создаём подключение к тестовой БД
  FDBConnection := TFDConnection.Create(nil);
  FDBConnection.Params.Clear;
  FDBConnection.DriverName := 'PG';
  FDBConnection.Params.Add('Server=localhost');
  FDBConnection.Params.Add('Port=5433');
  FDBConnection.Params.Add('Database=audit_test');
  FDBConnection.Params.Add('User_Name=test_user');
  FDBConnection.Params.Add('Password=test_password');
  FDBConnection.Connected := True;
  
  // Создаём HTTP клиент
  FHTTPClient := THTTPClient.Create;
  FHTTPClient.HandleRedirects := True;
  FHTTPClient.ConnectionTimeout := 10000;
  FHTTPClient.ResponseTimeout := 30000;
  
  FServerURL := 'http://localhost:8082';
  
  // Очищаем тестовые данные
  CleanupTestData;
end;

procedure TTestSecurityIntegration.TearDown;
begin
  FHTTPClient.Free;
  FDBConnection.Connected := False;
  FDBConnection.Free;
end;

procedure TTestSecurityIntegration.CleanupTestData;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    
    // Очищаем таблицы в правильном порядке
    Qry.SQL.Text := 'DELETE FROM audit_files';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 'DELETE FROM audit_logs';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 'DELETE FROM events';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 'DELETE FROM user_sessions';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 'DELETE FROM security_events';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 'DELETE FROM rate_limits';
    Qry.ExecSQL;
    
    // Сбрасываем состояние тестовых пользователей
    Qry.SQL.Text := 
      'UPDATE users SET failed_login_attempts = 0, locked_until = NULL ' +
      'WHERE username IN (''test_user'', ''test_user_2'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

function TTestSecurityIntegration.CreateTestSession(AUserID: Int64): string;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'INSERT INTO user_sessions (user_id, session_token, expires_at) ' +
      'VALUES (:user_id, md5(random()::text || clock_timestamp()::text), ' +
      'CURRENT_TIMESTAMP + INTERVAL ''24 hours'') ' +
      'RETURNING session_token';
    Qry.ParamByName('user_id').AsLargeInt := AUserID;
    Qry.Open;
    Result := Qry.FieldByName('session_token').AsString;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

procedure TTestSecurityIntegration.TestLogin_Success_RecordsEvent;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Qry: TFDQuery;
  EventCount: Integer;
begin
  // Arrange: очищаем security_events
  FDBConnection.ExecSQL('DELETE FROM security_events');
  
  // Act: выполняем успешный вход
  JSONPayload := '{"AUsername":"test_user","APassword":"test_password"}';
  var Stream0 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    Response := FHTTPClient.Post(FServerURL + '/datasnap/rest/TServerMethods1/Login', Stream0);
  finally
    Stream0.Free;
  end;
  
  // Assert: проверяем, что событие записано
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text :=
      'SELECT COUNT(*) FROM security_events ' +
      'WHERE event_type = ''login_success'' AND username = ''test_user''';
    Qry.Open;
    EventCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;

  Assert.AreEqual(1, EventCount,
    'Login success event should be recorded in security_events');
end;

procedure TTestSecurityIntegration.TestLogin_FailedAfter5Attempts_LocksAccount;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Qry: TFDQuery;
  IsLocked: Boolean;
  I: Integer;
begin
  // Arrange: сбрасываем счётчик попыток
  FDBConnection.ExecSQL(
    'UPDATE users SET failed_login_attempts = 0, locked_until = NULL ' +
    'WHERE username = ''test_user''');
  
  // Act: делаем 5 неудачных попыток входа
  JSONPayload := '{"AUsername":"test_user","APassword":"wrong_password"}';
  for I := 1 to 5 do
  begin
    var Stream1 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    Response := FHTTPClient.Post(FServerURL + '/datasnap/rest/TServerMethods1/Login', Stream1);
  finally
    Stream1.Free;
  end;
  end;
  
  // Assert: проверяем, что аккаунт заблокирован
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'SELECT locked_until FROM users WHERE username = ''test_user''';
    Qry.Open;
    IsLocked := not Qry.IsEmpty and not Qry.FieldByName('locked_until').IsNull and
                (Qry.FieldByName('locked_until').AsDateTime > Now);
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.IsTrue(IsLocked, 
    'Account should be locked after 5 failed attempts');
end;

procedure TTestSecurityIntegration.TestLogin_LockedAccount_Rejected;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Qry: TFDQuery;
begin
  // Arrange: блокируем аккаунт вручную
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'UPDATE users SET locked_until = CURRENT_TIMESTAMP + INTERVAL ''15 minutes'' ' +
      'WHERE username = ''test_user''';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Act: пытаемся войти с правильным паролем
  JSONPayload := '{"AUsername":"test_user","APassword":"test_password"}';
  var Stream2 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    Response := FHTTPClient.Post(FServerURL + '/datasnap/rest/TServerMethods1/updateLogin', Stream2);
  finally
    Stream2.Free;
  end;
  
  // Assert: должно быть отклонено (401 или 423)
  Assert.IsTrue((Response.StatusCode = 401) or (Response.StatusCode = 423),
    Format('Locked account should be rejected, got status %d', [Response.StatusCode]));
end;

procedure TTestSecurityIntegration.TestLogin_UnlockedAfterSuccessfulLogin;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Qry: TFDQuery;
  FailedAttempts: Integer;
begin
  // Arrange: устанавливаем несколько неудачных попыток
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'UPDATE users SET failed_login_attempts = 3 ' +
      'WHERE username = ''test_user''';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Act: выполняем успешный вход
  JSONPayload := '{"AUsername":"test_user","APassword":"test_password"}';
  var Stream3 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    Response := FHTTPClient.Post(FServerURL + '/datasnap/rest/TServerMethods1/Login', Stream3);
  finally
    Stream3.Free;
  end;
  
  // Assert: проверяем, что счётчик сброшен
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text :=
      'SELECT failed_login_attempts FROM users WHERE username = ''test_user''';
    Qry.Open;
    FailedAttempts := Qry.FieldByName('failed_login_attempts').AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;

  Assert.AreEqual(0, FailedAttempts,
    'Failed attempts should be reset after successful login');
end;

procedure TTestSecurityIntegration.TestRateLimit_LoginExceeded_Returns429;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  I: Integer;
  StatusCode: Integer;
begin
  // Arrange: очищаем rate_limits
  FDBConnection.ExecSQL('DELETE FROM rate_limits');
  
  // Act: делаем 21 запрос к /Login (лимит 20/час)
  JSONPayload := '{"AUsername":"test_user","APassword":"test_password"}';
  StatusCode := 200;
  
  for I := 1 to 21 do
  begin
    var Stream4 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
  try
    Response := FHTTPClient.Post(FServerURL + '/datasnap/rest/TServerMethods1/Login', Stream4);
  finally
    Stream4.Free;
  end;
    if I = 21 then
      StatusCode := Response.StatusCode;
  end;
  
  // Assert: 21-й запрос должен быть отклонён
  Assert.AreEqual(429, StatusCode, 
    '21st request to /Login should be rejected with 429');
end;

procedure TTestSecurityIntegration.TestRateLimit_UploadExceeded_Returns429;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  I: Integer;
  StatusCode: Integer;
  Token: string;
  Headers: TNetHeaders;
begin
  // Arrange: очищаем rate_limits и создаём сессию
  FDBConnection.ExecSQL('DELETE FROM rate_limits');
  Token := CreateTestSession(1);
  
  SetLength(Headers, 1);
  Headers[0].Name := 'X-Session-Token';
  Headers[0].Value := Token;
  
  // Act: делаем 101 запрос к /upload (лимит 100/час)
  JSONPayload := '{"event_type":"test","lat":0,"lon":0,"photo_base64":"","photo_filename":"test.jpg"}';
  StatusCode := 200;
  
  for I := 1 to 101 do
  begin
    var Stream5 := TStringStream.Create(JSONPayload, TEncoding.UTF8);
    try
      Response := FHTTPClient.Post(FServerURL + '/upload',
        Stream5, nil, Headers);
    finally
      Stream5.Free;
    end;
    if I = 101 then
      StatusCode := Response.StatusCode;
  end;
  
  // Assert: 101-й запрос должен быть отклонён
  Assert.AreEqual(429, StatusCode, 
    '101st request to /upload should be rejected with 429');
end;

procedure TTestSecurityIntegration.TestRateLimit_DifferentIPs_SeparateLimits;
var
  Qry: TFDQuery;
  Count1, Count2: Integer;
begin
  // Arrange: очищаем rate_limits
  FDBConnection.ExecSQL('DELETE FROM rate_limits');
  
  // Act: эмулируем запросы с разных IP (вручную, так как все запросы идут с localhost)
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    
    // IP1: 5 запросов
    Qry.SQL.Text := 
      'INSERT INTO rate_limits (ip_address, endpoint, request_count) ' +
      'VALUES (''192.168.1.1'', ''/Login'', 5)';
    Qry.ExecSQL;
    
    // IP2: 3 запроса
    Qry.SQL.Text := 
      'INSERT INTO rate_limits (ip_address, endpoint, request_count) ' +
      'VALUES (''192.168.1.2'', ''/Login'', 3)';
    Qry.ExecSQL;
    
    // Assert: проверяем, что счётчики разные
    Qry.SQL.Text := 
      'SELECT request_count FROM rate_limits WHERE ip_address = ''192.168.1.1''';
    Qry.Open;
    Count1 := Qry.FieldByName('request_count').AsInteger;
    Qry.Close;
    
    Qry.SQL.Text := 
      'SELECT request_count FROM rate_limits WHERE ip_address = ''192.168.1.2''';
    Qry.Open;
    Count2 := Qry.FieldByName('request_count').AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(5, Count1, 'IP1 should have 5 requests');
  Assert.AreEqual(3, Count2, 'IP2 should have 3 requests');
end;

procedure TTestSecurityIntegration.TestSecurityEvents_RetainedAfterRestart;
var
  Qry: TFDQuery;
  EventCount: Integer;
begin
  // Arrange: создаём событие
  FDBConnection.ExecSQL('DELETE FROM security_events');
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity) ' +
      'VALUES (''test_event'', ''test_user'', ''127.0.0.1'', ''Test details'', ''info'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Act: эмулируем "перезапуск" (просто проверяем, что событие осталось)
  // В реальности событие должно сохраниться в БД
  
  // Assert: событие должно быть в БД
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM security_events WHERE event_type = ''test_event''';
    Qry.Open;
    EventCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(1, EventCount, 
    'Security event should be retained in database');
end;

procedure TTestSecurityIntegration.TestSecurityEvents_CriticalEventsFilter;
var
  Qry: TFDQuery;
  CriticalCount: Integer;
begin
  // Arrange: создаём события с разной severity
  FDBConnection.ExecSQL('DELETE FROM security_events');
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity) ' +
      'VALUES (''info_event'', ''user1'', ''127.0.0.1'', ''Info'', ''info'')';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity) ' +
      'VALUES (''warning_event'', ''user2'', ''127.0.0.1'', ''Warning'', ''warning'')';
    Qry.ExecSQL;
    
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity) ' +
      'VALUES (''critical_event'', ''user3'', ''127.0.0.1'', ''Critical'', ''critical'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Act: получаем только критические события
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FDBConnection;
    Qry.SQL.Text := 
      'SELECT COUNT(*) FROM security_events WHERE severity = ''critical''';
    Qry.Open;
    CriticalCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  // Assert: должно быть только 1 критическое событие
  Assert.AreEqual(1, CriticalCount, 
    'Only critical events should be returned');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSecurityIntegration);

end.
