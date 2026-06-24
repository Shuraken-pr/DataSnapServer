unit TestSecurityAuditor;

interface

uses
  DUnitX.TestFramework, FireDAC.Comp.Client, SecurityAuditor;

type
  /// <summary>
  /// Модульные тесты для TSecurityAuditor
  /// </summary>
  [TestFixture]
  TTestSecurityAuditor = class
  strict private
    FConnection: TFDConnection;
    FAuditor: TSecurityAuditor;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    /// <summary>Тест 1: Запись события создаёт запись в БД</summary>
    [Test]
    procedure TestLogEvent_CreatesRecord;
    
    /// <summary>Тест 2: Все поля заполняются корректно</summary>
    [Test]
    procedure TestLogEvent_WithAllFields;
    
    /// <summary>Тест 3: GetRecentEvents возвращает правильный диапазон</summary>
    [Test]
    procedure TestGetRecentEvents_ReturnsCorrectRange;
    
    /// <summary>Тест 4: GetCriticalEvents фильтрует по severity</summary>
    [Test]
    procedure TestGetCriticalEvents_FiltersCorrectly;
    
    /// <summary>Тест 5: GetEventsByUser фильтрует по пользователю</summary>
    [Test]
    procedure TestGetEventsByUser_FiltersCorrectly;
    
    /// <summary>Тест 6: CleanupOldEvents удаляет старые события</summary>
    [Test]
    procedure TestCleanupOldEvents_RemovesExpired;
  end;

implementation

uses
  System.SysUtils, FireDAC.Stan.Def, FireDAC.Phys.PG, FireDAC.Phys.PGDef,
  Data.DB;

{ TTestSecurityAuditor }

procedure TTestSecurityAuditor.Setup;
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
  
  // Очищаем таблицу security_events перед каждым тестом
  FConnection.ExecSQL('DELETE FROM security_events');
  
  // Создаём аудитора
  FAuditor := TSecurityAuditor.Create(FConnection);
end;

procedure TTestSecurityAuditor.TearDown;
begin
  FAuditor.Free;
  FConnection.Connected := False;
  FConnection.Free;
end;

procedure TTestSecurityAuditor.TestLogEvent_CreatesRecord;
var
  Qry: TFDQuery;
  InitialCount, FinalCount: Integer;
begin
  // Arrange: запоминаем количество записей
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM security_events';
    Qry.Open;
    InitialCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  // Act: записываем событие
  FAuditor.LogEvent('login_success', 'test_user', '127.0.0.1', 
    'Test login', ssInfo);
  
  // Assert: проверяем, что запись создана
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM security_events';
    Qry.Open;
    FinalCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(InitialCount + 1, FinalCount, 
    'One record should be created');
end;

procedure TTestSecurityAuditor.TestLogEvent_WithAllFields;
var
  Qry: TFDQuery;
  EventType, Username, IPAddress, UserAgent, Details, Severity: string;
begin
  // Act: записываем событие со всеми полями
  FAuditor.LogEvent('login_failed', 'test_user', '192.168.1.100',
    'Invalid password', ssWarning, 'Mozilla/5.0');
  
  // Assert: проверяем, что все поля заполнены
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT event_type, username, ip_address, user_agent, details, severity ' +
      'FROM security_events ORDER BY event_id DESC LIMIT 1';
    Qry.Open;
    
    Assert.IsFalse(Qry.IsEmpty, 'Record should exist');

    EventType := Qry.FieldByName('event_type').AsString;
    Username := Qry.FieldByName('username').AsString;
    IPAddress := Qry.FieldByName('ip_address').AsString;
    UserAgent := Qry.FieldByName('user_agent').AsString;
    Details := Qry.FieldByName('details').AsString;
    Severity := Qry.FieldByName('severity').AsString;
    
    Assert.AreEqual('login_failed', EventType, 'Event type should match');
    Assert.AreEqual('test_user', Username, 'Username should match');
    Assert.AreEqual('192.168.1.100', IPAddress, 'IP address should match');
    Assert.AreEqual('Mozilla/5.0', UserAgent, 'User agent should match');
    Assert.IsTrue(pos('Invalid password', Details) > 0, 'Details should match');
    Assert.AreEqual('warning', Severity, 'Severity should match');
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

procedure TTestSecurityAuditor.TestGetRecentEvents_ReturnsCorrectRange;
var
  Events: TArray<TSecurityEvent>;
  Qry: TFDQuery;
begin
  // Arrange: создаём несколько событий
  FAuditor.LogEvent('event1', 'user1', '127.0.0.1', 'Old event', ssInfo);
  
  // Ждём 1 секунду
  Sleep(1000);
  
  FAuditor.LogEvent('event2', 'user2', '127.0.0.1', 'Recent event', ssInfo);
  
  // Act: получаем события за последний час
  Events := FAuditor.GetRecentEvents(1);
  
  // Assert: должны быть оба события
  Assert.AreEqual(2, Length(Events), 'Both events should be returned');
  
  // Act: получаем события за последнюю секунду (примерно)
  // Создаём событие 2 часа назад вручную
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity, created_at) ' +
      'VALUES (''old_event'', ''user3'', ''127.0.0.1'', ''Very old'', ''info'', ' +
      'CURRENT_TIMESTAMP - INTERVAL ''2 hours'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Act: получаем события за последний час
  Events := FAuditor.GetRecentEvents(1);
  
  // Assert: должны быть только 2 события (не старое)
  Assert.AreEqual(2, Length(Events), 'Only recent events should be returned');
end;

procedure TTestSecurityAuditor.TestGetCriticalEvents_FiltersCorrectly;
var
  Events: TArray<TSecurityEvent>;
begin
  // Arrange: создаём события с разной severity
  FAuditor.LogEvent('info_event', 'user1', '127.0.0.1', 'Info', ssInfo);
  FAuditor.LogEvent('warning_event', 'user2', '127.0.0.1', 'Warning', ssWarning);
  FAuditor.LogEvent('critical_event', 'user3', '127.0.0.1', 'Critical', ssCritical);
  
  // Act: получаем критические события
  Events := FAuditor.GetCriticalEvents(24);
  
  // Assert: должно быть только 1 критическое событие
  Assert.AreEqual(1, Length(Events), 'Only critical events should be returned');
  Assert.AreEqual('critical_event', Events[0].EventType, 'Event type should match');
  Assert.AreEqual(ssCritical, Events[0].Severity, 'Severity should be critical');
end;

procedure TTestSecurityAuditor.TestGetEventsByUser_FiltersCorrectly;
var
  Events: TArray<TSecurityEvent>;
begin
  // Arrange: создаём события для разных пользователей
  FAuditor.LogEvent('event1', 'user1', '127.0.0.1', 'User1 event', ssInfo);
  FAuditor.LogEvent('event2', 'user2', '127.0.0.1', 'User2 event', ssInfo);
  FAuditor.LogEvent('event3', 'user1', '127.0.0.1', 'User1 event 2', ssInfo);
  
  // Act: получаем события для user1
  Events := FAuditor.GetEventsByUser('user1');
  
  // Assert: должно быть 2 события для user1
  Assert.AreEqual(2, Length(Events), 'Only user1 events should be returned');
  
  // Проверяем, что все события принадлежат user1
  for var Event in Events do
  begin
    Assert.AreEqual('user1', Event.Username, 'All events should belong to user1');
  end;
end;

procedure TTestSecurityAuditor.TestCleanupOldEvents_RemovesExpired;
var
  Qry: TFDQuery;
  InitialCount, FinalCount: Integer;
begin
  // Arrange: создаём старое событие (100 дней назад)
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'INSERT INTO security_events (event_type, username, ip_address, details, severity, created_at) ' +
      'VALUES (''old_event'', ''user1'', ''127.0.0.1'', ''Old event'', ''info'', ' +
      'CURRENT_TIMESTAMP - INTERVAL ''100 days'')';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Создаём новое событие
  FAuditor.LogEvent('new_event', 'user2', '127.0.0.1', 'New event', ssInfo);
  
  // Запоминаем количество записей
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM security_events';
    Qry.Open;
    InitialCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  // Act: очищаем события старше 90 дней
  FAuditor.CleanupOldEvents(90);
  
  // Assert: старое событие должно быть удалено
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT COUNT(*) FROM security_events';
    Qry.Open;
    FinalCount := Qry.Fields[0].AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
  
  Assert.AreEqual(InitialCount - 1, FinalCount, 
    'Old event should be deleted');
  
  // Проверяем, что новое событие осталось
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT event_type FROM security_events';
    Qry.Open;
    Assert.AreEqual('new_event', Qry.FieldByName('event_type').AsString, 
      'New event should remain');
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSecurityAuditor);

end.
