unit TestRateLimiter;

interface

uses
  DUnitX.TestFramework, FireDAC.Comp.Client, RateLimiter;

type
  /// <summary>
  /// Модульные тесты для TRateLimiter
  /// </summary>
  [TestFixture]
  TTestRateLimiter = class
  strict private
    FConnection: TFDConnection;
    FLimiter: TRateLimiter;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    /// <summary>Тест 1: В пределах лимита возвращает rlAllowed</summary>
    [Test]
    procedure TestCheckLimit_UnderLimit;
    
    /// <summary>Тест 2: Превышен лимит возвращает rlExceeded</summary>
    [Test]
    procedure TestCheckLimit_OverLimit;
    
    /// <summary>Тест 3: RecordRequest увеличивает счётчик</summary>
    [Test]
    procedure TestRecordRequest_IncrementsCounter;
    
    /// <summary>Тест 4: Разные endpoints имеют отдельные лимиты</summary>
    [Test]
    procedure TestDifferentEndpoints_SeparateLimits;
    
    /// <summary>Тест 5: Разные IP имеют отдельные лимиты</summary>
    [Test]
    procedure TestDifferentIPs_SeparateLimits;
    
    /// <summary>Тест 6: CleanupOldRecords удаляет старые записи</summary>
    [Test]
    procedure TestCleanupOldRecords_RemovesExpired;
    
    /// <summary>Тест 7: SetLimit переопределяет лимит по умолчанию</summary>
    [Test]
    procedure TestSetLimit_OverridesDefault;
  end;

implementation

uses
  System.SysUtils, FireDAC.Stan.Def, FireDAC.Phys.PG, FireDAC.Phys.PGDef,
  Data.DB;

{ TTestRateLimiter }

procedure TTestRateLimiter.Setup;
begin
  // Создаём тестовое подключение к тестовой БД
  FConnection := TFDConnection.Create(nil);
  FConnection.Params.Clear;
  FConnection.DriverName := 'PG';
  FConnection.Params.Add('Server=localhost');
  FConnection.Params.Add('Port=5433');
  FConnection.Params.Add('Database=audit_test');
  FConnection.Params.Add('User_Name=test_user');
  FConnection.Params.Add('Password=test_password');
  FConnection.Connected := True;
  
  // Очищаем таблицу rate_limits перед каждым тестом
  FConnection.ExecSQL('DELETE FROM rate_limits');
  
  // Создаём rate limiter
  FLimiter := TRateLimiter.Create(FConnection);
end;

procedure TTestRateLimiter.TearDown;
begin
  FLimiter.Free;
  FConnection.Connected := False;
  FConnection.Free;
end;

procedure TTestRateLimiter.TestCheckLimit_UnderLimit;
var
  Result: TRateLimitResult;
begin
  // Arrange: устанавливаем низкий лимит для теста
  FLimiter.SetLimit('/test_endpoint', 5);
  
  // Act: делаем 3 запроса (меньше лимита)
  for var I := 1 to 3 do
    FLimiter.RecordRequest('127.0.0.1', '/test_endpoint');
  
  Result := FLimiter.CheckLimit('127.0.0.1', '/test_endpoint');
  
  // Assert: должно быть разрешено
  Assert.AreEqual(rlAllowed, Result, 'Should be allowed when under limit');
end;

procedure TTestRateLimiter.TestCheckLimit_OverLimit;
var
  Result: TRateLimitResult;
begin
  // Arrange: устанавливаем низкий лимит для теста
  FLimiter.SetLimit('/test_endpoint', 5);
  
  // Act: делаем 6 запросов (больше лимита)
  for var I := 1 to 6 do
    FLimiter.RecordRequest('127.0.0.1', '/test_endpoint');
  
  Result := FLimiter.CheckLimit('127.0.0.1', '/test_endpoint');
  
  // Assert: должно быть отклонено
  Assert.AreEqual(rlExceeded, Result, 'Should be exceeded when over limit');
end;

procedure TTestRateLimiter.TestRecordRequest_IncrementsCounter;
var
  InitialCount, FinalCount: Integer;
begin
  // Arrange: запоминаем начальный счётчик
  InitialCount := FLimiter.GetCurrentCount('127.0.0.1', '/test_endpoint');
  
  // Act: записываем запрос
  FLimiter.RecordRequest('127.0.0.1', '/test_endpoint');
  
  // Assert: счётчик увеличился на 1
  FinalCount := FLimiter.GetCurrentCount('127.0.0.1', '/test_endpoint');
  Assert.AreEqual(InitialCount + 1, FinalCount, 'Counter should increment by 1');
end;

procedure TTestRateLimiter.TestDifferentEndpoints_SeparateLimits;
var
  Count1, Count2: Integer;
begin
  // Arrange: устанавливаем разные лимиты
  FLimiter.SetLimit('/endpoint1', 10);
  FLimiter.SetLimit('/endpoint2', 20);
  
  // Act: делаем запросы к разным endpoints
  for var I := 1 to 5 do
    FLimiter.RecordRequest('127.0.0.1', '/endpoint1');
  
  for var I := 1 to 3 do
    FLimiter.RecordRequest('127.0.0.1', '/endpoint2');
  
  // Assert: счётчики должны быть разными
  Count1 := FLimiter.GetCurrentCount('127.0.0.1', '/endpoint1');
  Count2 := FLimiter.GetCurrentCount('127.0.0.1', '/endpoint2');
  
  Assert.AreEqual(5, Count1, 'Endpoint1 should have 5 requests');
  Assert.AreEqual(3, Count2, 'Endpoint2 should have 3 requests');
end;

procedure TTestRateLimiter.TestDifferentIPs_SeparateLimits;
var
  Count1, Count2: Integer;
begin
  // Act: делаем запросы с разных IP
  for var I := 1 to 5 do
    FLimiter.RecordRequest('192.168.1.1', '/test_endpoint');
  
  for var I := 1 to 3 do
    FLimiter.RecordRequest('192.168.1.2', '/test_endpoint');
  
  // Assert: счётчики должны быть разными для разных IP
  Count1 := FLimiter.GetCurrentCount('192.168.1.1', '/test_endpoint');
  Count2 := FLimiter.GetCurrentCount('192.168.1.2', '/test_endpoint');
  
  Assert.AreEqual(5, Count1, 'IP1 should have 5 requests');
  Assert.AreEqual(3, Count2, 'IP2 should have 3 requests');
end;

procedure TTestRateLimiter.TestCleanupOldRecords_RemovesExpired;
var
  Qry: TFDQuery;
  InitialCount, FinalCount: Integer;
begin
  // Arrange: создаём старую запись (2 часа назад)
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'INSERT INTO rate_limits (ip_address, endpoint, request_count, window_start) ' +
      'VALUES (''127.0.0.1'', ''/old_endpoint'', 10, CURRENT_TIMESTAMP - INTERVAL ''2 hours'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Создаём новую запись
  FLimiter.RecordRequest('127.0.0.1', '/new_endpoint');
  
  // Запоминаем количество записей
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM rate_limits';
    Qry.Open;
    InitialCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  // Act: очищаем старые записи
  FLimiter.CleanupOldRecords;
  
  // Assert: старая запись должна быть удалена
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM rate_limits';
    Qry.Open;
    FinalCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(InitialCount - 1, FinalCount, 'Old record should be deleted');
end;

procedure TTestRateLimiter.TestSetLimit_OverridesDefault;
var
  Limit: Integer;
begin
  // Arrange: проверяем стандартный лимит для /Login
  Limit := FLimiter.GetLimit('/Login');
  Assert.AreEqual(20, Limit, 'Default limit for /Login should be 20');
  
  // Act: переопределяем лимит
  FLimiter.SetLimit('/Login', 50);
  
  // Assert: лимит должен измениться
  Limit := FLimiter.GetLimit('/Login');
  Assert.AreEqual(50, Limit, 'Limit should be overridden to 50');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestRateLimiter);

end.
