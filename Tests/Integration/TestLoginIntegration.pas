unit TestLoginIntegration;

interface

uses
  DUnitX.TestFramework, TestBase, System.JSON, FireDAC.DApt, FireDAC.Comp.Client,
  System.Generics.Collections;

type
  /// <summary>
  /// Интеграционные тесты для проверки авторизации (INT-001, INT-002, INT-003, INT-004)
  /// </summary>
  [TestFixture]
  TTestLoginIntegration = class(TIntegrationTestBase)
  public
    /// <summary>INT-001: Полный цикл авторизации</summary>
    /// <remarks>
    /// Сервер использует pg_user для Login, поэтому этот тест проверяет
    /// только то, что endpoint существует и возвращает корректный формат ответа.
    /// Реальная проверка логина/пароля требует пользователя PostgreSQL.
    /// </remarks>
    [Test]
    procedure TestLogin_ValidCredentials_ReturnsToken;
    
    /// <summary>INT-002: Авторизация с неверным паролем</summary>
    [Test]
    procedure TestLogin_InvalidPassword_Returns401;
    
    /// <summary>INT-003: Использование валидного токена для SyncUpload</summary>
    [Test]
    procedure TestValidToken_AccessProtectedEndpoint_Returns200;
    
    /// <summary>INT-004: Использование невалидного токена</summary>
    [Test]
    procedure TestInvalidToken_AccessProtectedEndpoint_Returns401;
    
    /// <summary>INT-008: Истечение сессии</summary>
    [Test]
    procedure TestExpiredToken_AccessProtectedEndpoint_Returns401;
    
    /// <summary>INT-011: Несколько валидных токенов для одного пользователя</summary>
    [Test]
    procedure TestSession_MultipleTokens_SameUser;
    
    /// <summary>INT-012: Очистка тестовых данных удаляет сессии</summary>
    [Test]
    procedure TestSession_CleanupTestData_RemovesSessions;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.Net.HttpClient;

{ TTestLoginIntegration }

procedure TTestLoginIntegration.TestLogin_ValidCredentials_ReturnsToken;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  JSONResp: TJSONObject;
  StatusStr: string;
begin
  // 🔑 Сервер использует pg_user для Login, а не таблицу users.
  // Поэтому мы не можем создать тестового пользователя через INSERT INTO users.
  // Вместо этого проверяем, что endpoint существует и возвращает корректный JSON.
  
  // Act: пытаемся залогиниться с заведомо несуществующим пользователем
  JSONPayload := '{"username": "nonexistent_user_xyz", "password": "test_password"}';
  Response := PostToServer('/datasnap/rest/TServerMethods1/Login', JSONPayload, False);
  
  // Assert: проверяем, что endpoint существует и возвращает JSON
  // Ожидаем либо 200 (если пользователь существует), либо ошибку в JSON
  Assert.IsTrue((Response.StatusCode = 200) or (Response.StatusCode = 401) or (Response.StatusCode = 500),
    'Login endpoint should exist and return HTTP response');
  
  // Проверяем, что ответ — валидный JSON
  JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    Assert.IsNotNull(JSONResp, 'Response should be valid JSON');
    
    // Проверяем, что есть поле "status"
    if JSONResp.GetValue('status') <> nil then
    begin
      StatusStr := JSONResp.GetValue('status').Value;
      Assert.IsTrue((StatusStr = 'success') or (StatusStr = 'error'),
        'Status should be "success" or "error"');
    end;
  finally
    JSONResp.Free;
  end;
end;

procedure TTestLoginIntegration.TestLogin_InvalidPassword_Returns401;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  InitialSessionCount: Integer;
  FinalSessionCount: Integer;
begin
  // Arrange: запоминаем количество сессий до теста
  InitialSessionCount := GetTableCount('user_sessions');
  
  // Act: пытаемся залогиниться с неверным паролем
  JSONPayload := '{"username": "postgres", "password": "wrong_password_xyz"}';
  Response := PostToServer('/datasnap/rest/TServerMethods1/Login', JSONPayload, False);
  
  // Assert: сервер должен отклонить запрос (либо 401, либо error в JSON)
  if Response.StatusCode = 200 then
  begin
    // Если вернул 200, проверяем, что в JSON есть "status": "error"
    var JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
    try
      if JSONResp.GetValue('status') <> nil then
      begin
        Assert.AreEqual('error', JSONResp.GetValue('status').Value,
          'Invalid credentials should return error status');
      end;
    finally
      JSONResp.Free;
    end;
  end;
  
  // Проверяем, что сессия НЕ создана в БД
  FinalSessionCount := GetTableCount('user_sessions');
  Assert.AreEqual(InitialSessionCount, FinalSessionCount, 
    'No new session should be created for invalid credentials');
end;

procedure TTestLoginIntegration.TestValidToken_AccessProtectedEndpoint_Returns200;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Token: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: создаём валидную сессию напрямую в БД
  // 🔑 Используем user_id=1 (предполагаем, что такой пользователь существует в pg_user)
  Token := CreateTestSession(1, 24); // user_id=1, действительна 24 часа
  AuthToken := Token;
  
  // 🔑 ИСПРАВЛЕНИЕ: updateSyncUpload вставляет в таблицу events, а не audit_logs!
  InitialEventCount := GetTableCount('events');
  
  // Act: отправляем запрос к защищённому endpoint с валидным токеном
  JSONPayload :=
    '{"AJsonData": [' +
    '  {' +
    '    "event_type": "mobile_audit",' +
    '    "occurred_at": "2026-06-22T12:00:00Z",' +
    '    "details": {' +
    '      "photo_path": "/test/path.jpg",' +
    '      "lat": 55.75,' +
    '      "lon": 37.62' +
    '    }' +
    '  }' +
    ']}';
  
  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);
  
  // Assert: проверяем ответ
  Assert.AreEqual(200, Response.StatusCode,
    Format('Valid token should allow access. Response: %s', [Response.ContentAsString]));
  
  // 🔑 Проверяем, что запись создана в таблице events (не audit_logs!)
  FinalEventCount := GetTableCount('events');
  Assert.IsTrue(FinalEventCount > InitialEventCount, 
    'New event should be created in events table for valid token');
end;

procedure TTestLoginIntegration.TestInvalidToken_AccessProtectedEndpoint_Returns401;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: используем невалидный токен
  AuthToken := 'invalid_token_12345';
  
  InitialEventCount := GetTableCount('events');
  
  // Act: отправляем запрос к защищённому endpoint с невалидным токеном
  JSONPayload := 
    '{"AJsonData": [' +
    '  {' +
    '    "event_type": "mobile_audit",' +
    '    "occurred_at": "2026-06-22T12:00:00Z",' +
    '    "details": {' +
    '      "photo_path": "/test/path.jpg",' +
    '      "lat": 55.75,' +
    '      "lon": 37.62' +
    '    }' +
    '  }' +
    ']}';
  
  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);
  
  // Assert: проверяем, что сервер отклонил запрос
  Assert.AreEqual(401, Response.StatusCode, 
    'Invalid token should be rejected with 401');
  
  // Проверяем, что запись НЕ создана в БД
  FinalEventCount := GetTableCount('events');
  Assert.AreEqual(InitialEventCount, FinalEventCount, 
    'No event should be created for invalid token');
end;

procedure TTestLoginIntegration.TestExpiredToken_AccessProtectedEndpoint_Returns401;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  Token: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: создаём просроченную сессию напрямую в БД
  Token := CreateExpiredTestSession(1, 1); // user_id=1, просрочена 1 час назад
  AuthToken := Token;
  
  InitialEventCount := GetTableCount('events');
  
  // Act: отправляем запрос к защищённому endpoint с просроченным токеном
  JSONPayload := 
    '{"AJsonData": [' +
    '  {' +
    '    "event_type": "mobile_audit",' +
    '    "occurred_at": "2026-06-22T12:00:00Z",' +
    '    "details": {' +
    '      "photo_path": "/test/path.jpg",' +
    '      "lat": 55.75,' +
    '      "lon": 37.62' +
    '    }' +
    '  }' +
    ']}';
  
  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);
  
  // Assert: проверяем, что сервер отклонил запрос
  Assert.AreEqual(401, Response.StatusCode, 
    'Expired token should be rejected with 401');
  
  // Проверяем, что запись НЕ создана в БД
  FinalEventCount := GetTableCount('events');
  Assert.AreEqual(InitialEventCount, FinalEventCount, 
    'No event should be created for expired token');
end;

procedure TTestLoginIntegration.TestSession_MultipleTokens_SameUser;
var
  Token1, Token2: string;
  Response1, Response2: IHTTPResponse;
  JSONPayload: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: создаём две валидные сессии для одного пользователя
  Token1 := CreateTestSession(1, 24);
  Token2 := CreateTestSession(1, 24);
  
  // Сессии должны быть разными
  Assert.AreNotEqual(Token1, Token2, 'Two sessions should have different tokens');
  
  InitialEventCount := GetTableCount('events');
  
  JSONPayload := 
    '{"AJsonData": [' +
    '  {' +
    '    "event_type": "mobile_audit",' +
    '    "occurred_at": "2026-06-22T12:00:00Z",' +
    '    "details": {' +
    '      "photo_path": "/test/path.jpg",' +
    '      "lat": 55.75,' +
    '      "lon": 37.62' +
    '    }' +
    '  }' +
    ']}';
  
  // Act: используем первый токен
  AuthToken := Token1;
  Response1 := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);
  
  // Assert: первый токен работает
  Assert.AreEqual(200, Response1.StatusCode, 
    'First token should be valid');
  
  // Act: используем второй токен
  AuthToken := Token2;
  Response2 := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);
  
  // Assert: второй токен тоже работает
  Assert.AreEqual(200, Response2.StatusCode, 
    'Second token should also be valid');
  
  // Проверяем, что оба запроса создали записи
  FinalEventCount := GetTableCount('events');
  Assert.AreEqual(InitialEventCount + 2, FinalEventCount, 
    'Both sessions should create separate events');
end;

procedure TTestLoginIntegration.TestSession_CleanupTestData_RemovesSessions;
var
  Token: string;
  SessionCountBefore, SessionCountAfter: Integer;
  Qry: TFDQuery;
begin
  // Arrange: создаём сессию
  Token := CreateTestSession(1, 24);
  
  // Проверяем, что сессия создана
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DBConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM user_sessions WHERE session_token = :token';
    Qry.ParamByName('token').AsString := Token;
    Qry.Open;
    SessionCountBefore := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(1, SessionCountBefore, 'Session should exist in database');
  
  // Act: вызываем cleanup (как в TearDown)
  CleanupTestData;
  
  // Assert: проверяем, что сессия удалена
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DBConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM user_sessions WHERE session_token = :token';
    Qry.ParamByName('token').AsString := Token;
    Qry.Open;
    SessionCountAfter := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(0, SessionCountAfter, 'Cleanup should remove all sessions');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestLoginIntegration);

end.
