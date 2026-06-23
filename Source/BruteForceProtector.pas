unit BruteForceProtector;

interface

uses
  System.SysUtils, FireDAC.Comp.Client, FireDAC.Stan.Param, Data.DB;

type
  /// <summary>
  /// Результат проверки brute-force защиты
  /// </summary>
  TBruteForceResult = (brOK, brAccountLocked, brTooManyAttempts);
  
  /// <summary>
  /// Защита от brute-force атак — блокировка аккаунтов после N неудачных попыток
  /// </summary>
  TBruteForceProtector = class
  strict private
    FConnection: TFDConnection;
    FMaxAttempts: Integer;
    FLockMinutes: Integer;
  public
    constructor Create(AConnection: TFDConnection; 
      AMaxAttempts: Integer = 5; ALockMinutes: Integer = 15);
    
    /// <summary>Проверяет, заблокирован ли аккаунт</summary>
    function IsAccountLocked(const AUsername: string): Boolean;
    
    /// <summary>Записывает неудачную попытку входа</summary>
    /// <returns>True, если аккаунт заблокирован после этой попытки</returns>
    function RecordFailedAttempt(const AUsername, AIPAddress: string): Boolean;
    
    /// <summary>Сбрасывает счётчик попыток при успешном входе</summary>
    procedure ResetFailedAttempts(const AUsername: string);
    
    /// <summary>Принудительно блокирует аккаунт</summary>
    procedure LockAccount(const AUsername: string; AMinutes: Integer);
    
    /// <summary>Принудительно разблокирует аккаунт</summary>
    procedure UnlockAccount(const AUsername: string);
    
    /// <summary>Получает количество неудачных попыток</summary>
    function GetFailedAttempts(const AUsername: string): Integer;
    
    /// <summary>Разблокирует все просроченные аккаунты</summary>
    function UnlockExpiredAccounts: Integer;
    
    property MaxAttempts: Integer read FMaxAttempts;
    property LockMinutes: Integer read FLockMinutes;
  end;

implementation

{ TBruteForceProtector }

constructor TBruteForceProtector.Create(AConnection: TFDConnection;
  AMaxAttempts, ALockMinutes: Integer);
begin
  inherited Create;
  FConnection := AConnection;
  FMaxAttempts := AMaxAttempts;
  FLockMinutes := ALockMinutes;
end;

function TBruteForceProtector.IsAccountLocked(const AUsername: string): Boolean;
var
  Qry: TFDQuery;
  LockedUntil: TDateTime;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT locked_until FROM users WHERE username = :username';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.Open;
    
    Result := False;
    if not Qry.IsEmpty and not Qry.FieldByName('locked_until').IsNull then
    begin
      LockedUntil := Qry.FieldByName('locked_until').AsDateTime;
      Result := LockedUntil > Now;
    end;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TBruteForceProtector.RecordFailedAttempt(
  const AUsername, AIPAddress: string): Boolean;
var
  Qry: TFDQuery;
  NewAttempts: Integer;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    
    // Увеличиваем счётчик
    Qry.SQL.Text := 
      'UPDATE users SET failed_login_attempts = failed_login_attempts + 1 ' +
      'WHERE username = :username ' +
      'RETURNING failed_login_attempts';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.Open;
    
    NewAttempts := 0;
    if not Qry.IsEmpty then
      NewAttempts := Qry.Fields[0].AsInteger;
    Qry.Close;
    
    // Если достигли лимита — блокируем
    if NewAttempts >= FMaxAttempts then
    begin
      LockAccount(AUsername, FLockMinutes);
      Result := True;
    end
    else
      Result := False;
  finally
    Qry.Free;
  end;
end;

procedure TBruteForceProtector.ResetFailedAttempts(const AUsername: string);
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'UPDATE users SET failed_login_attempts = 0, locked_until = NULL, ' +
      'last_login_at = CURRENT_TIMESTAMP WHERE username = :username';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

procedure TBruteForceProtector.LockAccount(const AUsername: string; 
  AMinutes: Integer);
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'UPDATE users SET locked_until = CURRENT_TIMESTAMP + ' +
      '(:minutes || '' minutes'')::INTERVAL WHERE username = :username';
    Qry.ParamByName('minutes').AsInteger := AMinutes;
    Qry.ParamByName('username').AsString := AUsername;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

procedure TBruteForceProtector.UnlockAccount(const AUsername: string);
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'UPDATE users SET locked_until = NULL, failed_login_attempts = 0 ' +
      'WHERE username = :username';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

function TBruteForceProtector.GetFailedAttempts(const AUsername: string): Integer;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT failed_login_attempts FROM users WHERE username = :username';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.Open;
    
    Result := 0;
    if not Qry.IsEmpty then
      Result := Qry.FieldByName('failed_login_attempts').AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TBruteForceProtector.UnlockExpiredAccounts: Integer;
begin
  Result := FConnection.ExecSQL('SELECT unlock_expired_accounts()');
end;

end.
