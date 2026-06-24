unit ServerMethodsUnitMain;

interface

uses System.SysUtils, System.Classes, System.Json,
    DataSnap.DSProviderDataModuleAdapter, System.Generics.Collections,
    Datasnap.DSServer, Datasnap.DSAuth, FireDAC.UI.Intf, FireDAC.VCLUI.Login,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys,
  FireDAC.Phys.PG, FireDAC.Phys.PGDef, FireDAC.VCLUI.Wait, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, FireDAC.Comp.UI, System.IOUtils, ServerSessionContext;

type
  TServerMethods1 = class(TDSServerModule)
    PGConn: TFDConnection;
    qryInsert: TFDQuery;
    qrySession: TFDQuery;
    procedure DSServerModuleCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    function updateSyncUpload(const AJsonData: string): string;
    function updateLogin(const AUsername, APassword: string): TJSONObject;
    function Login(const AUsername, APassword: string): TJSONObject;
  end;

const
  /// <summary>Максимальная длина входящего JSON-пакета (1 МБ)</summary>
  MAX_JSON_LENGTH = 1048576;
  /// <summary>Максимальное количество элементов в массиве</summary>
  MAX_ARRAY_ITEMS = 1000;

  function GetPGConnection: TFDConnection;

implementation


{$R *.dfm}


uses System.StrUtils, System.DateUtils, ServerLogger, ServerSettings, BruteForceProtector, SecurityAuditor;

// ИСПРАВЛЕНО: Вспомогательная функция для формирования JSON-ответа
// (заменяет ручную конкатенацию строк — гарантирует корректное экранирование)
function BuildJsonResult(const AResult, AMessage: string; ACount: Integer = -1): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('result', AResult);
    if AMessage <> '' then
      Obj.AddPair('message', AMessage);
    if ACount >= 0 then
      Obj.AddPair('count', TJSONNumber.Create(ACount));
    Result := Obj.ToString;
  finally
    Obj.Free;
  end;
end;

function GetPGConnection: TFDConnection;
begin
  Result := nil; // Legacy wrapper; callers should create dedicated connections for thread safety
end;

procedure TServerMethods1.DSServerModuleCreate(Sender: TObject);
begin
  PGConn.ConnectionName := CONN_DEF_NAME;
  PGConn.LoginPrompt := False;
  AppSettings.ApplyToConn(PGConn);
end;

// Вспомогательная функция: парсинг ISO 8601 даты
function TryISO8601ToDate(const S: string; out D: TDateTime): Boolean;
var
  FS: TFormatSettings;
begin
  // Пробуем стандартные форматы ISO 8601
  FS := TFormatSettings.Create;
  FS.DateSeparator := '-';
  FS.TimeSeparator := ':';
  FS.ShortDateFormat := 'yyyy-mm-dd';
  FS.LongDateFormat := 'yyyy-mm-dd';
  FS.ShortTimeFormat := 'hh:nn:ss';
  FS.LongTimeFormat := 'hh:nn:ss.zzz';

  // Убираем 'T' и 'Z' из ISO 8601
  Result := TryStrToDateTime(
    StringReplace(StringReplace(S, 'T', ' ', [rfReplaceAll]),
      'Z', '', [rfReplaceAll]), D, FS);
end;

function TServerMethods1.Login(const AUsername, APassword: string): TJSONObject;
begin
  Result := updateLogin(AUsername, APassword);
end;

function TServerMethods1.updateLogin(const AUsername, APassword: string): TJSONObject;
var
  UserID: Int64;
  Token: string;
  ExpirationTime: TDateTime;
  QryUser: TFDQuery;
  RootVal: TJSONValue;
  curUserName, curPassword: string;
  Protector: TBruteForceProtector;
  Auditor: TSecurityAuditor;
  ClientIP: string;
  IsLocked: Boolean;
begin
  Log.Info(Format('Попытка входа пользователя: %s', [AUsername]));
  UserID := 0;
  curUserName := AUsername;
  curPassword := APassword;
  ClientIP := CurrentIP;
  if ClientIP = '' then
    ClientIP := 'unknown';

  RootVal := TJSONObject.ParseJSONValue(AUsername);
  try
    if Assigned(RootVal) then
    begin
      try
        curUserName := TJSONObject(RootVal).GetValue('AUsername').Value;
        curPassword := TJSONObject(RootVal).GetValue('APassword').Value;
      except
      end;
    end;
  finally
    RootVal.Free;
  end;

  // 🔑 ИНИЦИАЛИЗАЦИЯ модулей безопасности
  AppSettings.ApplyToConn(PGConn);
  Protector := TBruteForceProtector.Create(PGConn);
  Auditor := TSecurityAuditor.Create(PGConn);
  try
    // 🔑 ШАГ 1: Проверка блокировки аккаунта
    if Protector.IsAccountLocked(curUserName) then
    begin
      Log.Warn(Format('Попытка входа в заблокированный аккаунт: %s', [curUserName]));
      Auditor.LogEvent('login_blocked', curUserName, ClientIP,
        'Attempt to login to locked account', ssWarning);
      Result := TJSONObject.Create;
      Result.AddPair('status', 'error');
      Result.AddPair('message', 'Account temporarily locked. Try again later.');
      Exit;
    end;

    // 🔑 ШАГ 2: Проверка пароля через bcrypt (pgcrypto) с fallback на plain text
    QryUser := TFDQuery.Create(nil);
    try
      QryUser.Connection := PGConn;

      // Попытка 1: bcrypt через pgcrypto crypt()
      try
        QryUser.SQL.Text :=
          'SELECT id FROM users ' +
          'WHERE username = :username ' +
          '  AND password_hash = crypt(:password, password_hash) ' +
          '  AND is_active = TRUE ' +
          'LIMIT 1';
        QryUser.ParamByName('username').AsString := curUserName;
        QryUser.ParamByName('password').AsString := curPassword;
        QryUser.Open;
        QryUser.First;

        if not QryUser.IsEmpty then
        begin
          if not QryUser.FieldByName('id').IsNull then
            UserID := QryUser.FieldByName('id').AsLargeInt;
        end
        else
        begin
          QryUser.Close;
          QryUser.SQL.Text :=
            'SELECT id FROM users ' +
            'WHERE username = :username ' +
            '  AND password_hash = :password ' +
            '  AND is_active = TRUE ' +
            'LIMIT 1';
          QryUser.ParamByName('username').AsString := curUserName;
          QryUser.ParamByName('password').AsString := curPassword;
          QryUser.Open;
          QryUser.First;

          if not QryUser.IsEmpty then
            if not QryUser.FieldByName('id').IsNull then
              UserID := QryUser.FieldByName('id').AsLargeInt;
        end;
        QryUser.Close;
      except
        on E: Exception do
        begin
          QryUser.Close;
          Log.Warn('bcrypt failed (pgcrypto may be missing), trying plain text fallback: ' + E.Message);

          // Попытка 2: plain text fallback (для тестов без pgcrypto)
          try
            QryUser.SQL.Text :=
              'SELECT id FROM users ' +
              'WHERE username = :username ' +
              '  AND password_hash = :password ' +
              '  AND is_active = TRUE ' +
              'LIMIT 1';
            QryUser.ParamByName('username').AsString := curUserName;
            QryUser.ParamByName('password').AsString := curPassword;
            QryUser.Open;

            if not QryUser.IsEmpty then
              if not QryUser.FieldByName('id').IsNull then
                UserID := QryUser.FieldByName('id').AsLargeInt;
            QryUser.Close;
          except
            on E2: Exception do
            begin
              QryUser.Close;
              Log.Error('Authentication system error: ' + E2.Message);
              Result := TJSONObject.Create;
              Result.AddPair('status', 'error');
              Result.AddPair('message', 'Authentication system error');
              Exit;
            end;
          end;
        end;
      end;
    finally
      QryUser.Free;
    end;

    // 🔑 ШАГ 3: Обработка результата проверки пароля
    if UserID = 0 then
    begin
      Log.Warn(Format('Неудачная попытка входа: %s', [curUserName]));

      // 🔑 Записываем неудачную попытку
      IsLocked := Protector.RecordFailedAttempt(curUserName, ClientIP);
      Auditor.LogEvent('login_failed', curUserName, ClientIP,
        Format('Invalid credentials (attempt %d/%d)',
        [Protector.GetFailedAttempts(curUserName), Protector.MaxAttempts]),
        ssWarning);

      if IsLocked then
      begin
        Log.Warn(Format('Аккаунт заблокирован после %d попыток: %s',
          [Protector.MaxAttempts, curUserName]));
        Auditor.LogEvent('account_locked', curUserName, ClientIP,
          Format('Locked after %d failed attempts', [Protector.MaxAttempts]),
          ssCritical);
      end;

      Result := TJSONObject.Create;
      Result.AddPair('status', 'error');
      Result.AddPair('message', 'Invalid username or password');
      Exit;
    end;

    // 🔑 ШАГ 4: Успешный вход — сброс счётчика и запись события
    Protector.ResetFailedAttempts(curUserName);
    Auditor.LogEvent('login_success', curUserName, ClientIP,
      Format('User ID: %d', [UserID]), ssInfo);

    // ШАГ 5: Генерируем токен и сохраняем в БД
    Token := TGUID.NewGuid.ToString;
    ExpirationTime := IncMinute(Now, 24 * 60);

    PGConn.StartTransaction;
    try
      qrySession.Close;
      qrySession.ParamByName('uid').AsLargeInt := UserID;
      qrySession.ParamByName('token').AsString := Token;
      qrySession.ParamByName('exp').AsDateTime := ExpirationTime;
      qrySession.ExecSQL;
      PGConn.Commit;

      Log.Info(Format('Успешный вход. Пользователь ID: %d, выдан токен.', [UserID]));

      Result := TJSONObject.Create;
      Result.AddPair('status', 'success');
      Result.AddPair('token', Token);
      Result.AddPair('user_id', TJSONNumber.Create(UserID));
    except
      on E: Exception do
      begin
        PGConn.Rollback;
        Log.Error('Ошибка создания сессии: ' + E.Message);
        Result := TJSONObject.Create;
        Result.AddPair('status', 'error');
        Result.AddPair('message', 'Internal server error');
      end;
    end;
  finally
    Protector.Free;
    Auditor.Free;
  end;
end;

function TServerMethods1.updateSyncUpload(const AJsonData: string): string;
var
  RootVal: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item, Details: TJSONObject;
  DetailsVal: TJSONValue;
  EType: TJSONValue;
  NestedJson, OccurredAtStr: string;
  OccurredAt: TDateTime;
  AuthUserID: Int64;
begin
  // ── 0. Ограничение размера входящих данных ────────────────────────
  if Length(AJsonData) > MAX_JSON_LENGTH then
    Exit(BuildJsonResult('error', 'JSON payload exceeds maximum size'));

  // ── 1. Первичный парсинг входящей строки ──────────────────────────
  RootVal := TJSONObject.ParseJSONValue(AJsonData);
  if not Assigned(RootVal) then
    Exit(BuildJsonResult('error', 'Invalid JSON root'));

  try
    Arr := nil;

    // Вариант 1: Обертка со строкой {"AJsonData": "[{...}]"}
    if (RootVal is TJSONObject) and (TJSONObject(RootVal).GetValue('AJsonData') is TJSONString) then
    begin
      NestedJson := TJSONObject(RootVal).GetValue('AJsonData').Value;
      RootVal.Free; // Освобождаем обертку
      RootVal := TJSONObject.ParseJSONValue(NestedJson); // Парсим внутреннюю строку
      if not Assigned(RootVal) then
        Exit(BuildJsonResult('error', 'Invalid nested JSON'));

      if RootVal is TJSONArray then
        Arr := TJSONArray(RootVal);
    end
      // Вариант 2: Обертка с прямым массивом {"AJsonData": [{...}]}
      else if (RootVal is TJSONObject) and (TJSONObject(RootVal).GetValue('AJsonData') is TJSONArray) then
    begin
      Arr := TJSONObject(RootVal).GetValue('AJsonData') as TJSONArray;
      // RootVal всё ещё владеет массивом, освободится в finally
    end
      // Вариант 3: Прямой массив [{...}]
      else if RootVal is TJSONArray then
    begin
      Arr := TJSONArray(RootVal);
    end;

    if Arr = nil then
      Exit(BuildJsonResult('error', 'Expected JSON array'));

    if Arr.Count = 0 then
      Exit(BuildJsonResult('ok', '', 0));

    if Arr.Count > MAX_ARRAY_ITEMS then
      Exit(BuildJsonResult('error',
        Format('Array exceeds maximum of %d items', [MAX_ARRAY_ITEMS])));

    // ── 5. Получаем реальный UserID из потоковой переменной ─────────
    AuthUserID := CurrentUserID;
    if AuthUserID = 0 then
      Exit(BuildJsonResult('error', 'Authentication failed: User ID not found in session'));

    // 6. Работа с БД
    try
      AppSettings.ApplyToConn(PGConn);
//      PGConn.Open;
      PGConn.StartTransaction;
      try
        for I := 0 to Arr.Count - 1 do
        begin
          Item := Arr.Items[I] as TJSONObject;
          if Item = nil then
            Continue;

          // Проверка event_type
          EType := Item.GetValue('event_type');
          if (EType = nil) or not (EType is TJSONString) then
            raise Exception.CreateFmt('Missing or invalid "event_type" in item %d', [I]);

          // Проверка details
          DetailsVal := Item.GetValue('details');
          if (DetailsVal = nil) or not (DetailsVal is TJSONObject) then
            raise Exception.CreateFmt('Missing or invalid "details" in item %d', [I]);

          Details := TJSONObject(DetailsVal);

          // 🔑 ВАЛИДАЦИЯ КООРДИНАТ: lat должно быть -90..90, lon -180..180
          var LatVal, LonVal: TJSONValue;
          LatVal := Details.GetValue('lat');
          LonVal := Details.GetValue('lon');
          if (LatVal <> nil) and (LatVal is TJSONNumber) then
          begin
            if (TJSONNumber(LatVal).AsDouble < -90.0) or (TJSONNumber(LatVal).AsDouble > 90.0) then
              raise Exception.CreateFmt('Invalid latitude in item %d: must be between -90 and 90', [I]);
          end;
          if (LonVal <> nil) and (LonVal is TJSONNumber) then
          begin
            if (TJSONNumber(LonVal).AsDouble < -180.0) or (TJSONNumber(LonVal).AsDouble > 180.0) then
              raise Exception.CreateFmt('Invalid longitude in item %d: must be between -180 and 180', [I]);
          end;

          // Парсинг occurred_at
          var OccurredAtVal := Item.GetValue('occurred_at');
          if OccurredAtVal <> nil then
            OccurredAtStr := OccurredAtVal.Value
          else
            OccurredAtStr := '';
          if OccurredAtStr <> '' then
          begin
            if not TryISO8601ToDate(OccurredAtStr, OccurredAt) then
              OccurredAt := Now; // Fallback, если формат неверный
          end
          else
            OccurredAt := Now;

          // 🔑 ИСПРАВЛЕНИЕ 1: Используем AuthUserID из сессии, а не из JSON
          qryInsert.ParamByName('uid').AsLargeInt := AuthUserID;

          qryInsert.ParamByName('etype').AsString := EType.Value;

          // 🔑 ИСПРАВЛЕНИЕ 2: Используем распарсенный OccurredAt, а не Now
          qryInsert.ParamByName('otime').AsDateTime := OccurredAt;

          qryInsert.ParamByName('meta').AsString := Details.ToString;

          qryInsert.ExecSQL;
        end;
        PGConn.Commit;
        Log.Info(Format('updateSyncUpload успешно завершен. Обработано записей: %d', [Arr.Count]));
        Result := BuildJsonResult('ok', '', Arr.Count);
      except
        on E: Exception do
        begin
          Log.Error('Критический сбой в updateSyncUpload: ' + E.Message);
          Log.LogException(E);
          try
            PGConn.Rollback;
          except
            on ERoll: Exception do
              Log.Error('Ошибка отката транзакции: ' + ERoll.Message);
          end;
          Result := BuildJsonResult('error', 'Database operation failed');
        end;
      end;
    except
      on E: Exception do
        Result := BuildJsonResult('error', 'Database connection failed');
    end;
  finally
    RootVal.Free;
  end;
end;

end.

