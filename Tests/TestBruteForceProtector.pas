unit TestBruteForceProtector;

interface

uses
  DUnitX.TestFramework, FireDAC.Comp.Client, FireDAC.Stan.Async, BruteForceProtector;

type
  /// <summary>
  /// Модульные тесты для TBruteForceProtector
  /// </summary>
  [TestFixture]
  TTestBruteForceProtector = class
  strict private
    FConnection: TFDConnection;
    FProtector: TBruteForceProtector;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    /// <summary>Тест 1: Не заблокированный аккаунт возвращает False</summary>
    [Test]
    procedure TestIsAccountLocked_NotLocked;
    
    /// <summary>Тест 2: Заблокированный аккаунт возвращает True</summary>
    [Test]
    procedure TestIsAccountLocked_Locked;
    
    /// <summary>Тест 3: RecordFailedAttempt увеличивает счётчик</summary>
    [Test]
    procedure TestRecordFailedAttempt_IncrementsCounter;
    
    /// <summary>Тест 4: Автоблокировка после 5 попыток</summary>
    [Test]
    procedure TestRecordFailedAttempt_LocksAfterMaxAttempts;
    
    /// <summary>Тест 5: ResetFailedAttempts сбрасывает счётчик</summary>
    [Test]
    procedure TestResetFailedAttempts_ClearsCounter;
    
    /// <summary>Тест 6: LockAccount устанавливает время блокировки</summary>
    [Test]
    procedure TestLockAccount_SetsLockedUntil;
    
    /// <summary>Тест 7: UnlockAccount снимает блокировку</summary>
    [Test]
    procedure TestUnlockAccount_ClearsLock;
    
    /// <summary>Тест 8: GetFailedAttempts возвращает правильное значение</summary>
    [Test]
    procedure TestGetFailedAttempts_ReturnsCorrectValue;
  end;

implementation

uses
  System.SysUtils, FireDAC.Stan.Def, FireDAC.Phys.PG, FireDAC.Phys.PGDef,
  Data.DB;

{ TTestBruteForceProtector }

procedure TTestBruteForceProtector.Setup;
var
  Qry: TFDQuery;
begin
  // Создаём тестовое подключение к тестовой БД
  FConnection := TFDConnection.Create(nil);
  FConnection.Params.Clear;
  FConnection.Params.DriverID := 'PG';
  FConnection.Params.Add('Server=localhost');
  FConnection.Params.Add('Port=5433');
  FConnection.Params.Add('Database=audit_test');
  FConnection.Params.Add('User_Name=test_user');
  FConnection.Params.Add('Password=test_password');
  FConnection.Connected := True;
  
  // Создаём тестового пользователя, если его нет
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'INSERT INTO users (username, password_hash) ' +
      'VALUES (''brute_test_user'', ''test_hash'') ' +
      'ON CONFLICT (username) DO NOTHING';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Сбрасываем состояние пользователя
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'UPDATE users SET failed_login_attempts = 0, locked_until = NULL ' +
      'WHERE username = ''brute_test_user''';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  // Создаём протектор с параметрами по умолчанию (5 попыток, 15 минут)
  FProtector := TBruteForceProtector.Create(FConnection);
end;

procedure TTestBruteForceProtector.TearDown;
var
  Qry: TFDQuery;
begin
  FProtector.Free;
  
  // Удаляем тестового пользователя
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'DELETE FROM users WHERE username = ''brute_test_user''';
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
  
  FConnection.Connected := False;
  FConnection.Free;
end;

procedure TTestBruteForceProtector.TestIsAccountLocked_NotLocked;
begin
  // Act & Assert: аккаунт не заблокирован
  Assert.IsFalse(FProtector.IsAccountLocked('brute_test_user'), 
    'Account should not be locked initially');
end;

procedure TTestBruteForceProtector.TestIsAccountLocked_Locked;
begin
  // Arrange: блокируем аккаунт
  FProtector.LockAccount('brute_test_user', 15);
  
  // Act & Assert: аккаунт заблокирован
  Assert.IsTrue(FProtector.IsAccountLocked('brute_test_user'), 
    'Account should be locked after LockAccount');
end;

procedure TTestBruteForceProtector.TestRecordFailedAttempt_IncrementsCounter;
var
  InitialAttempts, FinalAttempts: Integer;
begin
  // Arrange: запоминаем начальное количество попыток
  InitialAttempts := FProtector.GetFailedAttempts('brute_test_user');
  
  // Act: записываем неудачную попытку
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  
  // Assert: счётчик увеличился на 1
  FinalAttempts := FProtector.GetFailedAttempts('brute_test_user');
  Assert.AreEqual(InitialAttempts + 1, FinalAttempts, 
    'Failed attempts should increment by 1');
end;

procedure TTestBruteForceProtector.TestRecordFailedAttempt_LocksAfterMaxAttempts;
var
  I: Integer;
  IsLocked: Boolean;
begin
  // Arrange: сбрасываем счётчик
  FProtector.ResetFailedAttempts('brute_test_user');
  IsLocked := false;
  
  // Act: делаем 5 неудачных попыток (максимум)
  for I := 1 to FProtector.MaxAttempts do
  begin
    IsLocked := FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  end;
  
  // Assert: аккаунт должен быть заблокирован
  Assert.IsTrue(IsLocked, 'Account should be locked after max attempts');
  Assert.IsTrue(FProtector.IsAccountLocked('brute_test_user'), 
    'IsAccountLocked should return True');
end;

procedure TTestBruteForceProtector.TestResetFailedAttempts_ClearsCounter;
var
  Attempts: Integer;
begin
  // Arrange: делаем несколько неудачных попыток
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  
  // Act: сбрасываем счётчик
  FProtector.ResetFailedAttempts('brute_test_user');
  
  // Assert: счётчик должен быть 0
  Attempts := FProtector.GetFailedAttempts('brute_test_user');
  Assert.AreEqual(0, Attempts, 'Failed attempts should be reset to 0');
  
  // Assert: аккаунт не должен быть заблокирован
  Assert.IsFalse(FProtector.IsAccountLocked('brute_test_user'), 
    'Account should not be locked after reset');
end;

procedure TTestBruteForceProtector.TestLockAccount_SetsLockedUntil;
var
  Qry: TFDQuery;
  LockedUntil: TDateTime;
begin
  // Act: блокируем аккаунт на 15 минут
  FProtector.LockAccount('brute_test_user', 15);
  
  // Assert: проверяем, что locked_until установлен
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT locked_until FROM users WHERE username = ''brute_test_user''';
    Qry.Open;
    
    Assert.IsFalse(Qry.IsEmpty, 'User should exist');
    Assert.IsFalse(Qry.FieldByName('locked_until').IsNull, 
      'locked_until should be set');
    
    LockedUntil := Qry.FieldByName('locked_until').AsDateTime;
    Assert.IsTrue(LockedUntil > Now, 
      'locked_until should be in the future');
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

procedure TTestBruteForceProtector.TestUnlockAccount_ClearsLock;
var
  Qry: TFDQuery;
begin
  // Arrange: блокируем аккаунт
  FProtector.LockAccount('brute_test_user', 15);
  Assert.IsTrue(FProtector.IsAccountLocked('brute_test_user'), 
    'Account should be locked');
  
  // Act: разблокируем аккаунт
  FProtector.UnlockAccount('brute_test_user');
  
  // Assert: аккаунт не должен быть заблокирован
  Assert.IsFalse(FProtector.IsAccountLocked('brute_test_user'), 
    'Account should not be locked after unlock');
  
  // Assert: счётчик попыток должен быть 0
  Assert.AreEqual(0, FProtector.GetFailedAttempts('brute_test_user'), 
    'Failed attempts should be 0 after unlock');
  
  // Assert: проверяем, что locked_until NULL
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT locked_until FROM users WHERE username = ''brute_test_user''';
    Qry.Open;
    
    Assert.IsTrue(Qry.FieldByName('locked_until').IsNull, 
      'locked_until should be NULL after unlock');
    
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

procedure TTestBruteForceProtector.TestGetFailedAttempts_ReturnsCorrectValue;
var
  Attempts: Integer;
begin
  // Arrange: сбрасываем счётчик
  FProtector.ResetFailedAttempts('brute_test_user');
  
  // Act: делаем 3 неудачные попытки
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  FProtector.RecordFailedAttempt('brute_test_user', '127.0.0.1');
  
  // Assert: GetFailedAttempts должен вернуть 3
  Attempts := FProtector.GetFailedAttempts('brute_test_user');
  Assert.AreEqual(3, Attempts, 'Failed attempts should be 3');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestBruteForceProtector);

end.
