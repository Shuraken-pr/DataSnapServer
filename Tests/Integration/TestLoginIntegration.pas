unit TestLoginIntegration;

interface

uses
  DUnitX.TestFramework, TestBase, System.JSON, FireDAC.DApt, FireDAC.Comp.Client,
  FireDAC.Stan.Param, System.Generics.Collections;

type
  /// <summary>
  /// Интеграционные тесты для проверки авторизации (INT-001, INT-002, INT-003, INT-004)
  /// </summary>
  [TestFixture]
  TTestLoginIntegration = class(TIntegrationTestBase)
  public
    /// <summary>INT-001: Полный цикл авторизации</summary>
    /// <remarks>
    /// Сервер использует собственную таблицу users с bcrypt (pgcrypto) для Login.
    /// Тестовый пользователь test_user/test_password создан в init-test-db.sql.
    /// </remarks>
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
  JSONResp: TJSONObject;
  JSONPayload: string;
  StatusStr: string;
  Token: string;
begin
  // 🔑 ИСПРАВЛЕНИЕ: Используем тестового пользователя из таблицы users (bcrypt)
  // test_user / test_password создан в init-test-db.sql через pgcrypto

  // Act: логин с валидными credentials (POST с JSON body — DataSnap REST ожидает параметры в JSON)
  JSONPayload := '{"AUsername":"test_user","APassword":"test_password"}';
  Response := PostToServer('/datasnap/rest/TServerMethods1/Login', JSONPayload, False);

  // Assert: должен вернуться 200 и токен
  Assert.AreEqual(200, Response.StatusCode,
    Format('Valid login should return HTTP 200. Response: %s', [Response.ContentAsString]));

  JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    Assert.IsNotNull(JSONResp, 'Response should be valid JSON');

    // DataSnap REST оборачивает в {"result": [...]}
    var ResultArr := JSONResp.GetValue('result') as TJSONArray;
    Assert.IsNotNull(ResultArr, 'DataSnap should return result array');
    Assert.AreEqual(1, ResultArr.Count, 'Result array should have one element');

    // 🔑 Login возвращает TJSONObject (не string), поэтому DataSnap оборачивает его в TJSONObject
    var InnerObj := ResultArr.Items[0] as TJSONObject;
    Assert.IsNotNull(InnerObj, 'Inner response should be valid JSON');
    StatusStr := InnerObj.GetValue('status').Value;
    Assert.AreEqual('success', StatusStr, 'Status should be success');
    Token := InnerObj.GetValue('token').Value;
    Assert.IsTrue(Token <> '', 'Token should not be empty');
  finally
    JSONResp.Free;
  end;
end;

procedure TTestLoginIntegration.TestLogin_InvalidPassword_Returns401;
var
  Response: IHTTPResponse;
  InitialSessionCount: Integer;
  JSONPayload: string;
  FinalSessionCount: Integer;
begin
  // Arrange: запоминаем количество сессий до теста
  InitialSessionCount := GetTableCount('user_sessions');

  // Act: пытаемся залогиниться с неверным паролем (POST с JSON body)
  JSONPayload := '{"AUsername":"test_user","APassword":"wrong_password_xyz"}';
  Response := PostToServer('/datasnap/rest/TServerMethods1/Login', JSONPayload, False);

  // Assert: DataSnap возвращает 200 даже для ошибок, но в JSON status=error
  Assert.AreEqual(200, Response.StatusCode,
    Format('Login endpoint should return HTTP 200 with JSON error. Response: %s', [Response.ContentAsString]));

  var JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    Assert.IsNotNull(JSONResp, 'Response should be valid JSON');

    // DataSnap REST оборачивает в {"result": [...]}
    var ResultArr := JSONResp.GetValue('result') as TJSONArray;
    Assert.IsNotNull(ResultArr, 'DataSnap should return result array');
    Assert.AreEqual(1, ResultArr.Count, 'Result array should have one element');

    // 🔑 Login возвращает TJSONObject (не string), поэтому DataSnap оборачивает его в TJSONObject
    var InnerObj := ResultArr.Items[0] as TJSONObject;
    Assert.IsNotNull(InnerObj, 'Inner response should be valid JSON');
    Assert.AreEqual('error', InnerObj.GetValue('status').Value,
      'Invalid credentials should return error status');
    
    // 🔑 Проверяем, что это именно ошибка credentials, а не системная ошибка (pgcrypto)
    var MsgVal := InnerObj.GetValue('message');
    if MsgVal <> nil then
      Assert.AreEqual('Invalid username or password', MsgVal.Value,
        Format('Should be credentials error, not system error. Full response: %s', [InnerObj.ToString]));
  finally
    JSONResp.Free;
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
  // 🔑 Используем тестового пользователя из таблицы users (bcrypt)
  Token := CreateTestSession(GetTestUserID, 24); // действительна 24 часа
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
  Token := CreateExpiredTestSession(GetTestUserID, 1); // просрочена 1 час назад
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
  Token1 := CreateTestSession(GetTestUserID, 24);
  Token2 := CreateTestSession(GetTestUserID, 24);
  
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
  Token := CreateTestSession(GetTestUserID, 24);
  
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
