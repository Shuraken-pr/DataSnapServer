# 📋 Спецификация: Безопасность (финальная версия)

**Дата утверждения:** 2026-06-22  
**Статус:** ✅ Утверждена  
**Версия:** 1.0

---

## 1. 🎯 Цели и задачи

### 1.1. Назначение
Реализовать три уровня защиты сервера, используя уже созданную инфраструктуру БД:

| Уровень | Назначение | Статус БД | Статус кода |
|---------|------------|:---------:|:-----------:|
| **Brute-force защита** | Блокировка аккаунтов после N неудачных попыток | ✅ Готово | ⏳ В процессе |
| **Rate limiting** | Ограничение запросов по IP/endpoint | ✅ Готово | ⏳ В процессе |
| **Аудит безопасности** | Запись всех событий входа/блокировок | ✅ Готово | ⏳ В процессе |
| **Тесты** | Гарантия корректной работы | N/A | ⏳ В процессе |

### 1.2. Существующая инфраструктура (не нужно создавать)

**Таблицы БД (уже созданы миграцией 001):**
```sql
users (
    id, username, password_hash, role, is_active,
    last_login_at, failed_login_attempts, locked_until, updated_at
)
security_events (
    event_id, event_type, username, ip_address, user_agent,
    details, severity, created_at
)
rate_limits (
    id, ip_address, endpoint, request_count, window_start
)
```

**Функции БД (уже созданы):**
- `cleanup_rate_limits()` — очистка старых записей
- `unlock_expired_accounts()` — авторазблокировка
- `cleanup_expired_sessions()` — очистка сессий

**Серверный код (уже есть):**
- `pgcrypto` расширение для bcrypt
- `ServerSessionContext.pas` с `threadvar CurrentUserID`
- `updateLogin` с проверкой `crypt(:password, password_hash)`
- `WebModuleBeforeDispatch` с проверкой токена

---

## 2. 🛡️ Brute-force защита

### 2.1. Алгоритм работы

```
Запрос на Login:
  │
  ├─ 1. Получить IP клиента
  ├─ 2. Проверить, заблокирован ли аккаунт
  │     └─ SELECT locked_until FROM users WHERE username = :u
  │        └─ Если locked_until > NOW() → отклонить (401)
  │
  ├─ 3. Проверить пароль через bcrypt
  │     └─ SELECT id FROM users WHERE username = :u
  │        AND password_hash = crypt(:p, password_hash)
  │
  ├─ 4a. Если пароль НЕВЕРНЫЙ:
  │      ├─ UPDATE users SET failed_login_attempts = failed_login_attempts + 1
  │      ├─ Если failed_login_attempts >= 5:
  │      │   └─ UPDATE users SET locked_until = NOW() + 15 minutes
  │      ├─ INSERT INTO security_events (event_type='login_failed', ...)
  │      └─ Отклонить (401)
  │
  └─ 4b. Если пароль ВЕРНЫЙ:
         ├─ UPDATE users SET failed_login_attempts = 0, locked_until = NULL
         ├─ INSERT INTO security_events (event_type='login_success', ...)
         └─ Создать сессию и вернуть токен
```

### 2.2. Параметры

| Параметр | Значение | Обоснование |
|----------|:--------:|-------------|
| `MAX_FAILED_ATTEMPTS` | 5 | Баланс удобства и безопасности |
| `LOCK_DURATION_MINUTES` | 15 | Достаточно для предотвращения brute-force |
| `LOCK_DURATION_HOURS` (макс) | 24 | Для повторяющихся атак |

### 2.3. Модуль `BruteForceProtector.pas`

```pascal
unit BruteForceProtector;

interface

uses
  System.SysUtils, FireDAC.Comp.Client;

type
  TBruteForceResult = (brOK, brAccountLocked, brTooManyAttempts);
  
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
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT locked_until FROM users WHERE username = :username';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.Open;
    
    Result := not Qry.IsEmpty and 
              (not Qry.FieldByName('locked_until').IsNull) and
              (Qry.FieldByName('locked_until').AsDateTime > Now);
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
```

### 2.4. Интеграция в `ServerMethodsUnitMain.pas`

```pascal
function TServerMethods1.updateLogin(const AUsername, APassword: string): string;
var
  Qry: TFDQuery;
  UserID: Int64;
  Token: string;
  Protector: TBruteForceProtector;
  Auditor: TSecurityAuditor;
  ClientIP: string;
  IsLocked: Boolean;
begin
  Result := '';
  ClientIP := GetClientIP;
  Protector := TBruteForceProtector.Create(WebModuleData.PGConn);
  Auditor := TSecurityAuditor.Create(WebModuleData.PGConn);
  try
    // 🔑 1. Проверка блокировки
    if Protector.IsAccountLocked(AUsername) then
    begin
      Auditor.LogEvent('login_blocked', AUsername, ClientIP, 
        'Account temporarily locked', ssWarning);
      raise EAuthenticationException.Create('Account locked. Try again later.');
    end;
    
    // 🔑 2. Проверка пароля через bcrypt (существующий код)
    Qry := TFDQuery.Create(nil);
    try
      Qry.Connection := WebModuleData.PGConn;
      Qry.SQL.Text := 
        'SELECT id FROM users WHERE username = :username ' +
        'AND password_hash = crypt(:password, password_hash) ' +
        'AND is_active = TRUE';
      Qry.ParamByName('username').AsString := AUsername;
      Qry.ParamByName('password').AsString := APassword;
      Qry.Open;
      
      if Qry.IsEmpty then
      begin
        // 🔑 3. Неудачная попытка
        IsLocked := Protector.RecordFailedAttempt(AUsername, ClientIP);
        
        Auditor.LogEvent('login_failed', AUsername, ClientIP, 
          Format('Invalid credentials (attempt %d)', 
          [Protector.GetFailedAttempts(AUsername)]), ssWarning);
        
        if IsLocked then
        begin
          Auditor.LogEvent('account_locked', AUsername, ClientIP, 
            Format('Locked after %d failed attempts', 
            [Protector.MaxAttempts]), ssCritical);
        end;
        
        raise EAuthenticationException.Create('Invalid credentials');
      end;
      
      UserID := Qry.FieldByName('id').AsLargeInt;
      Qry.Close;
    finally
      Qry.Free;
    end;
    
    // 🔑 4. Успешный вход
    Protector.ResetFailedAttempts(AUsername);
    Auditor.LogEvent('login_success', AUsername, ClientIP, 'OK', ssInfo);
    
    // 5. Создание сессии (существующий код)
    Token := GenerateSessionToken;
    // ... INSERT INTO user_sessions ...
    
    Result := Token;
  finally
    Protector.Free;
    Auditor.Free;
  end;
end;
```

---

## 3. 🚦 Rate limiting

### 3.1. Алгоритм — Fixed Window

```
Каждый запрос:
  │
  ├─ 1. Получить IP клиента и endpoint
  ├─ 2. Проверить счётчик за текущее окно (1 час)
  │     └─ SELECT request_count FROM rate_limits
  │        WHERE ip_address = :ip AND endpoint = :ep
  │        AND window_start > CURRENT_TIMESTAMP - INTERVAL '1 hour'
  │
  ├─ 3a. Если счётчик >= лимит:
  │      ├─ INSERT INTO security_events (event_type='rate_limit_exceeded', ...)
  │      └─ Вернуть HTTP 429 Too Many Requests
  │
  └─ 3b. Если счётчик < лимит:
         ├─ INSERT INTO rate_limits ... ON CONFLICT DO UPDATE
         │   SET request_count = request_count + 1
         └─ Продолжить обработку запроса
```

### 3.2. Лимиты для endpoints

| Endpoint | Лимит (запросов/час) | Обоснование |
|----------|:-------------------:|-------------|
| `/Login` | 20 | Защита от brute-force |
| `/upload` | 100 | Ограничение загрузки файлов |
| `/SyncUpload` | 200 | Синхронизация данных |
| Прочие | 500 | Общий лимит |

### 3.3. Модуль `RateLimiter.pas`

```pascal
unit RateLimiter;

interface

uses
  System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client;

type
  TRateLimitResult = (rlAllowed, rlExceeded);
  
  TRateLimiter = class
  strict private
    FConnection: TFDConnection;
    FLimits: TDictionary<string, Integer>;
    FWindowMinutes: Integer;
  public
    constructor Create(AConnection: TFDConnection; AWindowMinutes: Integer = 60);
    destructor Destroy; override;
    
    /// <summary>Проверяет, не превышен ли лимит</summary>
    function CheckLimit(const AIPAddress, AEndpoint: string): TRateLimitResult;
    
    /// <summary>Записывает запрос в счётчик</summary>
    procedure RecordRequest(const AIPAddress, AEndpoint: string);
    
    /// <summary>Устанавливает лимит для endpoint</summary>
    procedure SetLimit(const AEndpoint: string; ALimit: Integer);
    
    /// <summary>Получает лимит для endpoint</summary>
    function GetLimit(const AEndpoint: string): Integer;
    
    /// <summary>Очищает старые записи (старше окна)</summary>
    procedure CleanupOldRecords;
    
    /// <summary>Получает текущий счётчик для IP/endpoint</summary>
    function GetCurrentCount(const AIPAddress, AEndpoint: string): Integer;
  end;

implementation

{ TRateLimiter }

constructor TRateLimiter.Create(AConnection: TFDConnection; 
  AWindowMinutes: Integer);
begin
  inherited Create;
  FConnection := AConnection;
  FWindowMinutes := AWindowMinutes;
  FLimits := TDictionary<string, Integer>.Create;
  
  // Стандартные лимиты
  FLimits.Add('/Login', 20);
  FLimits.Add('/datasnap/rest/TServerMethods1/Login', 20);
  FLimits.Add('/upload', 100);
  FLimits.Add('/datasnap/rest/TServerMethods1/SyncUpload', 200);
  FLimits.Add('*', 500);  // Лимит по умолчанию
end;

destructor TRateLimiter.Destroy;
begin
  FLimits.Free;
  inherited;
end;

function TRateLimiter.CheckLimit(const AIPAddress, AEndpoint: string): TRateLimitResult;
var
  Qry: TFDQuery;
  CurrentCount, Limit: Integer;
begin
  Limit := GetLimit(AEndpoint);
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT COALESCE(SUM(request_count), 0) as total ' +
      'FROM rate_limits ' +
      'WHERE ip_address = :ip AND endpoint = :endpoint ' +
      'AND window_start > CURRENT_TIMESTAMP - (:minutes || '' minutes'')::INTERVAL';
    Qry.ParamByName('ip').AsString := AIPAddress;
    Qry.ParamByName('endpoint').AsString := AEndpoint;
    Qry.ParamByName('minutes').AsInteger := FWindowMinutes;
    Qry.Open;
    
    CurrentCount := Qry.FieldByName('total').AsInteger;
    Qry.Close;
    
    if CurrentCount >= Limit then
      Result := rlExceeded
    else
      Result := rlAllowed;
  finally
    Qry.Free;
  end;
end;

procedure TRateLimiter.RecordRequest(const AIPAddress, AEndpoint: string);
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'INSERT INTO rate_limits (ip_address, endpoint, request_count, window_start) ' +
      'VALUES (:ip, :endpoint, 1, CURRENT_TIMESTAMP) ' +
      'ON CONFLICT (ip_address, endpoint) DO UPDATE ' +
      'SET request_count = rate_limits.request_count + 1 ' +
      'WHERE rate_limits.window_start > CURRENT_TIMESTAMP - (:minutes || '' minutes'')::INTERVAL';
    Qry.ParamByName('ip').AsString := AIPAddress;
    Qry.ParamByName('endpoint').AsString := AEndpoint;
    Qry.ParamByName('minutes').AsInteger := FWindowMinutes;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

procedure TRateLimiter.SetLimit(const AEndpoint: string; ALimit: Integer);
begin
  FLimits.AddOrSetValue(AEndpoint, ALimit);
end;

function TRateLimiter.GetLimit(const AEndpoint: string): Integer;
begin
  if not FLimits.TryGetValue(AEndpoint, Result) then
    FLimits.TryGetValue('*', Result);
end;

procedure TRateLimiter.CleanupOldRecords;
begin
  FConnection.ExecSQL('SELECT cleanup_rate_limits()');
end;

function TRateLimiter.GetCurrentCount(const AIPAddress, AEndpoint: string): Integer;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT COALESCE(SUM(request_count), 0) as total ' +
      'FROM rate_limits WHERE ip_address = :ip AND endpoint = :endpoint';
    Qry.ParamByName('ip').AsString := AIPAddress;
    Qry.ParamByName('endpoint').AsString := AEndpoint;
    Qry.Open;
    Result := Qry.FieldByName('total').AsInteger;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

end.
```

### 3.4. Интеграция в `WebModuleUnitMain.pas`

```pascal
procedure TWebModule1.WebModuleBeforeDispatch(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  RateLimiter: TRateLimiter;
  ClientIP, Endpoint: string;
  Auditor: TSecurityAuditor;
begin
  ClientIP := GetClientIP(Request);
  Endpoint := Request.PathInfo;
  
  // 🔑 Rate limiting
  RateLimiter := TRateLimiter.Create(PGConn);
  try
    if RateLimiter.CheckLimit(ClientIP, Endpoint) = rlExceeded then
    begin
      Auditor := TSecurityAuditor.Create(PGConn);
      try
        Auditor.LogEvent('rate_limit_exceeded', '', ClientIP,
          Format('Endpoint: %s', [Endpoint]), ssWarning);
      finally
        Auditor.Free;
      end;
      
      Response.StatusCode := 429;
      Response.Content := '{"error":"Too Many Requests"}';
      Response.ContentType := 'application/json';
      Handled := True;
      Exit;
    end;
    
    RateLimiter.RecordRequest(ClientIP, Endpoint);
  finally
    RateLimiter.Free;
  end;
  
  // ... существующая проверка токена ...
end;
```

---

## 4. 📝 Аудит безопасности

### 4.1. Модуль `SecurityAuditor.pas`

```pascal
unit SecurityAuditor;

interface

uses
  System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client;

type
  TSecuritySeverity = (ssInfo, ssWarning, ssCritical);
  
  TSecurityEvent = record
    EventID: Int64;
    EventType: string;
    Username: string;
    IPAddress: string;
    UserAgent: string;
    Details: string;
    Severity: TSecuritySeverity;
    CreatedAt: TDateTime;
  end;
  
  TSecurityAuditor = class
  strict private
    FConnection: TFDConnection;
    function SeverityToString(ASeverity: TSecuritySeverity): string;
    function StringToSeverity(const AValue: string): TSecuritySeverity;
  public
    constructor Create(AConnection: TFDConnection);
    
    /// <summary>Записывает событие безопасности</summary>
    procedure LogEvent(
      const AEventType: string;
      const AUsername: string;
      const AIPAddress: string;
      const ADetails: string;
      ASeverity: TSecuritySeverity = ssInfo;
      const AUserAgent: string = ''
    );
    
    /// <summary>Получает события за последние N часов</summary>
    function GetRecentEvents(AHours: Integer = 24): TArray<TSecurityEvent>;
    
    /// <summary>Получает события по пользователю</summary>
    function GetEventsByUser(const AUsername: string): TArray<TSecurityEvent>;
    
    /// <summary>Получает критические события</summary>
    function GetCriticalEvents(AHours: Integer = 24): TArray<TSecurityEvent>;
    
    /// <summary>Получает события по IP</summary>
    function GetEventsByIP(const AIPAddress: string): TArray<TSecurityEvent>;
    
    /// <summary>Очищает старые события (старше N дней)</summary>
    procedure CleanupOldEvents(ADays: Integer = 90);
  end;

implementation

uses
  System.JSON;

{ TSecurityAuditor }

constructor TSecurityAuditor.Create(AConnection: TFDConnection);
begin
  inherited Create;
  FConnection := AConnection;
end;

function TSecurityAuditor.SeverityToString(ASeverity: TSecuritySeverity): string;
begin
  case ASeverity of
    ssInfo: Result := 'info';
    ssWarning: Result := 'warning';
    ssCritical: Result := 'critical';
  else
    Result := 'info';
  end;
end;

function TSecurityAuditor.StringToSeverity(const AValue: string): TSecuritySeverity;
begin
  if SameText(AValue, 'warning') then
    Result := ssWarning
  else if SameText(AValue, 'critical') then
    Result := ssCritical
  else
    Result := ssInfo;
end;

procedure TSecurityAuditor.LogEvent(
  const AEventType, AUsername, AIPAddress, ADetails: string;
  ASeverity: TSecuritySeverity;
  const AUserAgent: string);
var
  Qry: TFDQuery;
  DetailsJSON: string;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    
    // Формируем JSON для details
    DetailsJSON := Format('{"message": %s}', [
      TJSONObject(TJSONPair.Create('message', ADetails)).ToString
    ]);
    
    Qry.SQL.Text := 
      'INSERT INTO security_events ' +
      '(event_type, username, ip_address, user_agent, details, severity) ' +
      'VALUES (:event_type, :username, :ip_address, :user_agent, ' +
      ':details::jsonb, :severity)';
    Qry.ParamByName('event_type').AsString := AEventType;
    
    if AUsername <> '' then
      Qry.ParamByName('username').AsString := AUsername
    else
      Qry.ParamByName('username').Clear;
    
    Qry.ParamByName('ip_address').AsString := AIPAddress;
    
    if AUserAgent <> '' then
      Qry.ParamByName('user_agent').AsString := AUserAgent
    else
      Qry.ParamByName('user_agent').Clear;
    
    Qry.ParamByName('details').AsString := ADetails;
    Qry.ParamByName('severity').AsString := SeverityToString(ASeverity);
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

function TSecurityAuditor.GetRecentEvents(AHours: Integer): TArray<TSecurityEvent>;
var
  Qry: TFDQuery;
  Events: TList<TSecurityEvent>;
  Event: TSecurityEvent;
begin
  Events := TList<TSecurityEvent>.Create;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT * FROM security_events ' +
      'WHERE created_at > CURRENT_TIMESTAMP - (:hours || '' hours'')::INTERVAL ' +
      'ORDER BY created_at DESC';
    Qry.ParamByName('hours').AsInteger := AHours;
    Qry.Open;
    
    while not Qry.Eof do
    begin
      Event.EventID := Qry.FieldByName('event_id').AsLargeInt;
      Event.EventType := Qry.FieldByName('event_type').AsString;
      Event.Username := Qry.FieldByName('username').AsString;
      Event.IPAddress := Qry.FieldByName('ip_address').AsString;
      Event.UserAgent := Qry.FieldByName('user_agent').AsString;
      Event.Details := Qry.FieldByName('details').AsString;
      Event.Severity := StringToSeverity(Qry.FieldByName('severity').AsString);
      Event.CreatedAt := Qry.FieldByName('created_at').AsDateTime;
      Events.Add(Event);
      Qry.Next;
    end;
    Qry.Close;
    
    Result := Events.ToArray;
  finally
    Qry.Free;
    Events.Free;
  end;
end;

function TSecurityAuditor.GetEventsByUser(const AUsername: string): TArray<TSecurityEvent>;
var
  Qry: TFDQuery;
  Events: TList<TSecurityEvent>;
  Event: TSecurityEvent;
begin
  Events := TList<TSecurityEvent>.Create;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT * FROM security_events WHERE username = :username ' +
      'ORDER BY created_at DESC';
    Qry.ParamByName('username').AsString := AUsername;
    Qry.Open;
    
    while not Qry.Eof do
    begin
      Event.EventID := Qry.FieldByName('event_id').AsLargeInt;
      Event.EventType := Qry.FieldByName('event_type').AsString;
      Event.Username := Qry.FieldByName('username').AsString;
      Event.IPAddress := Qry.FieldByName('ip_address').AsString;
      Event.UserAgent := Qry.FieldByName('user_agent').AsString;
      Event.Details := Qry.FieldByName('details').AsString;
      Event.Severity := StringToSeverity(Qry.FieldByName('severity').AsString);
      Event.CreatedAt := Qry.FieldByName('created_at').AsDateTime;
      Events.Add(Event);
      Qry.Next;
    end;
    Qry.Close;
    
    Result := Events.ToArray;
  finally
    Qry.Free;
    Events.Free;
  end;
end;

function TSecurityAuditor.GetCriticalEvents(AHours: Integer): TArray<TSecurityEvent>;
var
  Qry: TFDQuery;
  Events: TList<TSecurityEvent>;
  Event: TSecurityEvent;
begin
  Events := TList<TSecurityEvent>.Create;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT * FROM security_events ' +
      'WHERE severity = ''critical'' ' +
      'AND created_at > CURRENT_TIMESTAMP - (:hours || '' hours'')::INTERVAL ' +
      'ORDER BY created_at DESC';
    Qry.ParamByName('hours').AsInteger := AHours;
    Qry.Open;
    
    while not Qry.Eof do
    begin
      Event.EventID := Qry.FieldByName('event_id').AsLargeInt;
      Event.EventType := Qry.FieldByName('event_type').AsString;
      Event.Username := Qry.FieldByName('username').AsString;
      Event.IPAddress := Qry.FieldByName('ip_address').AsString;
      Event.UserAgent := Qry.FieldByName('user_agent').AsString;
      Event.Details := Qry.FieldByName('details').AsString;
      Event.Severity := StringToSeverity(Qry.FieldByName('severity').AsString);
      Event.CreatedAt := Qry.FieldByName('created_at').AsDateTime;
      Events.Add(Event);
      Qry.Next;
    end;
    Qry.Close;
    
    Result := Events.ToArray;
  finally
    Qry.Free;
    Events.Free;
  end;
end;

function TSecurityAuditor.GetEventsByIP(const AIPAddress: string): TArray<TSecurityEvent>;
var
  Qry: TFDQuery;
  Events: TList<TSecurityEvent>;
  Event: TSecurityEvent;
begin
  Events := TList<TSecurityEvent>.Create;
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'SELECT * FROM security_events WHERE ip_address = :ip ' +
      'ORDER BY created_at DESC';
    Qry.ParamByName('ip').AsString := AIPAddress;
    Qry.Open;
    
    while not Qry.Eof do
    begin
      Event.EventID := Qry.FieldByName('event_id').AsLargeInt;
      Event.EventType := Qry.FieldByName('event_type').AsString;
      Event.Username := Qry.FieldByName('username').AsString;
      Event.IPAddress := Qry.FieldByName('ip_address').AsString;
      Event.UserAgent := Qry.FieldByName('user_agent').AsString;
      Event.Details := Qry.FieldByName('details').AsString;
      Event.Severity := StringToSeverity(Qry.FieldByName('severity').AsString);
      Event.CreatedAt := Qry.FieldByName('created_at').AsDateTime;
      Events.Add(Event);
      Qry.Next;
    end;
    Qry.Close;
    
    Result := Events.ToArray;
  finally
    Qry.Free;
    Events.Free;
  end;
end;

procedure TSecurityAuditor.CleanupOldEvents(ADays: Integer);
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 
      'DELETE FROM security_events ' +
      'WHERE created_at < CURRENT_TIMESTAMP - (:days || '' days'')::INTERVAL';
    Qry.ParamByName('days').AsInteger := ADays;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

end.
```

---

## 5. 🧪 Тесты

### 5.1. Модульные тесты (25 новых тестов)

#### `TestBruteForceProtector.pas` (8 тестов)

| № | Тест | Описание |
|---|------|----------|
| 1 | `TestIsAccountLocked_NotLocked` | Не заблокирован → False |
| 2 | `TestIsAccountLocked_Locked` | Заблокирован → True |
| 3 | `TestRecordFailedAttempt_IncrementsCounter` | Счётчик увеличивается |
| 4 | `TestRecordFailedAttempt_LocksAfterMaxAttempts` | Автоблокировка после 5 попыток |
| 5 | `TestResetFailedAttempts_ClearsCounter` | Сброс счётчика |
| 6 | `TestLockAccount_SetsLockedUntil` | Установка времени блокировки |
| 7 | `TestUnlockAccount_ClearsLock` | Снятие блокировки |
| 8 | `TestGetFailedAttempts_ReturnsCorrectValue` | Получение количества попыток |

#### `TestRateLimiter.pas` (7 тестов)

| № | Тест | Описание |
|---|------|----------|
| 1 | `TestCheckLimit_UnderLimit` | В пределах лимита → rlAllowed |
| 2 | `TestCheckLimit_OverLimit` | Превышен лимит → rlExceeded |
| 3 | `TestRecordRequest_IncrementsCounter` | Счётчик запросов |
| 4 | `TestDifferentEndpoints_SeparateLimits` | Разные лимиты для endpoints |
| 5 | `TestDifferentIPs_SeparateLimits` | Разные лимиты для IP |
| 6 | `TestCleanupOldRecords_RemovesExpired` | Очистка старых записей |
| 7 | `TestSetLimit_OverridesDefault` | Переопределение лимита |

#### `TestSecurityAuditor.pas` (6 тестов)

| № | Тест | Описание |
|---|------|----------|
| 1 | `TestLogEvent_CreatesRecord` | Запись создаётся |
| 2 | `TestLogEvent_WithAllFields` | Все поля заполняются |
| 3 | `TestGetRecentEvents_ReturnsCorrectRange` | Правильный диапазон |
| 4 | `TestGetCriticalEvents_FiltersCorrectly` | Фильтрация по severity |
| 5 | `TestGetEventsByUser_FiltersCorrectly` | Фильтрация по пользователю |
| 6 | `TestCleanupOldEvents_RemovesExpired` | Очистка старых событий |

#### `TestPasswordHasher.pas` (4 теста)

| № | Тест | Описание |
|---|------|----------|
| 1 | `TestHashPassword_ReturnsValidBcryptFormat` | Формат `$2a$12$...` |
| 2 | `TestHashPassword_DifferentHashesForSamePassword` | Солёность работает |
| 3 | `TestVerifyPassword_CorrectPassword` | Верный пароль → True |
| 4 | `TestVerifyPassword_WrongPassword` | Неверный пароль → False |

### 5.2. Интеграционные тесты (9 новых тестов)

#### `TestSecurityIntegration.pas` (9 тестов)

| № | ID | Тест | Описание |
|---|----|----|----------|
| 1 | SEC-001 | `TestLogin_Success_RecordsEvent` | Успешный вход записывается в аудит |
| 2 | SEC-002 | `TestLogin_FailedAfter5Attempts_LocksAccount` | Блокировка после 5 попыток |
| 3 | SEC-003 | `TestLogin_LockedAccount_Rejected` | Заблокированный аккаунт отклоняется |
| 4 | SEC-004 | `TestLogin_UnlockedAfterSuccessfulLogin` | Разблокировка после успешного входа |
| 5 | SEC-005 | `TestRateLimit_LoginExceeded_Returns429` | Rate limit для Login (20/час) |
| 6 | SEC-006 | `TestRateLimit_UploadExceeded_Returns429` | Rate limit для Upload (100/час) |
| 7 | SEC-007 | `TestRateLimit_DifferentIPs_SeparateLimits` | Разные лимиты для разных IP |
| 8 | SEC-008 | `TestSecurityEvents_RetainedAfterRestart` | События сохраняются |
| 9 | SEC-009 | `TestSecurityEvents_CriticalEventsFilter` | Фильтр критических событий |

---

## 6. ✅ Критерии приёмки

### 6.1. Обязательные критерии

- [ ] Модуль `BruteForceProtector.pas` реализован и протестирован
- [ ] Модуль `RateLimiter.pas` реализован и протестирован
- [ ] Модуль `SecurityAuditor.pas` реализован и протестирован
- [ ] Метод `updateLogin` интегрирует все три модуля
- [ ] `WebModuleBeforeDispatch` проверяет rate limits
- [ ] Все 25 модульных тестов проходят
- [ ] Все 9 интеграционных тестов проходят
- [ ] Общее количество тестов: **118** (84 текущих + 34 новых)
- [ ] Время полного прогона тестов: ≤ 30 секунд

### 6.2. Дополнительные критерии

- [ ] Документация обновлена (README.md, SECURITY.md)
- [ ] Создан скрипт для просмотра событий безопасности
- [ ] Создан скрипт для разблокировки пользователей

### 6.3. Метрики качества

| Метрика | Целевое значение |
|---------|------------------|
| **Время проверки rate limit** | < 5 мс на запрос |
| **Время записи события** | < 10 мс |
| **Покрытие кода** | ≥ 90% для новых модулей |
| **Стабильность тестов** | 100% (без flaky-тестов) |

---

## 7. 📅 План реализации

### Этап 1: Модуль `SecurityAuditor.pas` (2 часа)
- [x] Создать модуль
- [x] Написать 6 модульных тестов
- [ ] Интегрировать в `updateLogin`
- **Статус:** ✅ Завершено (модуль и тесты созданы)

### Этап 2: Модуль `BruteForceProtector.pas` (3 часа)
- [x] Создать модуль
- [x] Написать 8 модульных тестов
- [ ] Интегрировать в `updateLogin`
- [ ] Написать 4 интеграционных теста (SEC-001..004)
- **Статус:** ✅ Модуль и тесты созданы

### Этап 3: Модуль `RateLimiter.pas` (3 часа)
- [x] Создать модуль
- [x] Написать 7 модульных тестов
- [ ] Интегрировать в `WebModuleBeforeDispatch`
- [ ] Написать 3 интеграционных теста (SEC-005..007)
- **Статус:** ✅ Модуль и тесты созданы

### Этап 4: Модуль `PasswordHasher.pas` (1 час)
- [x] Создать обёртку над pgcrypto
- [x] Написать 4 модульных теста
- **Статус:** ✅ Завершено

### Этап 5: Финализация (2 часа)
- [x] Написать 9 интеграционных тестов (SEC-001..009)
- [x] Обновить документацию (создан SECURITY.md)
- [ ] Провести полный прогон всех тестов
- **Статус:** ✅ Почти завершено

**Итого:** ~11 часов работы

---

## 8. 📊 Ожидаемые результаты

После реализации спецификации:

| Метрика | До | После |
|---------|:--:|:-----:|
| **Общее количество тестов** | 84 | **118** |
| **Модульные тесты** | 71 | 96 |
| **Интеграционные тесты** | 13 | 22 |
| **Защита от brute-force** | ❌ Нет | ✅ Есть |
| **Rate limiting** | ❌ Нет | ✅ Есть |
| **Аудит безопасности** | ❌ Нет | ✅ Есть |
| **Модули безопасности** | 0 | 4 |
| **Покрытие критических процессов** | 70% | **95%** |

---

## 9. 🎯 Следующие шаги

1. ✅ **Утвердить спецификацию** — ВЫПОЛНЕНО
2. **Начать реализацию** с Этапа 1 (`SecurityAuditor.pas`)
3. **Последовательно внедрить** все модули
4. **Провести финальное тестирование**

---

## 10. 📝 История изменений

| Дата | Версия | Изменения |
|------|--------|-----------|
| 2026-06-22 | 1.0 | Утверждена финальная версия спецификации |

---

**Готовы начать реализацию?** 🚀
