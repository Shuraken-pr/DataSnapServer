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
    function Login(const AUsername, APassword: string): TJSONObject;
  end;

const
  /// <summary>Максимальная длина входящего JSON-пакета (1 МБ)</summary>
  MAX_JSON_LENGTH = 1048576;
  /// <summary>Максимальное количество элементов в массиве</summary>
  MAX_ARRAY_ITEMS = 1000;

implementation


{$R *.dfm}


uses System.StrUtils, System.DateUtils, ServerLogger, ServerSettings;

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

procedure TServerMethods1.DSServerModuleCreate(Sender: TObject);
begin
  PGConn.ConnectionName := CONN_DEF_NAME;
  PGConn.LoginPrompt := False;
end;

// Вспомогательная функция: парсинг ISO 8601 даты
function TryISO8601ToDate(const S: string; out D: TDateTime): Boolean;
var
  FS: TFormatSettings;
begin
  // Пробуем стандартные форматы ISO 8601
  FS := TFormatSettings.Create('en-US');
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
var
  UserID: Integer;
  Token: string;
  ExpirationTime: TDateTime;
  TempConn: TFDConnection;
begin
  Log.Info(Format('Попытка входа пользователя: %s', [AUsername]));
  UserID := 0;

  // ИСПРАВЛЕНИЕ: Используем временное соединение для проверки credentials
  TempConn := TFDConnection.Create(nil);
  try
    TempConn.ConnectionDefName := CONN_DEF_NAME;
    TempConn.LoginPrompt := False;
    TempConn.Params.UserName := AUsername;
    TempConn.Params.Password := APassword;

    try
      TempConn.Open;

      // Если соединение открылось, значит логин/пароль верны для СУБД.
      // Теперь получаем ID пользователя из таблицы users.
      var TempQry := TFDQuery.Create(nil);
      try
        TempQry.Connection := TempConn;
        TempQry.SQL.Text := 'SELECT usesysid as id FROM pg_user WHERE usename = :username';
        TempQry.ParamByName('username').AsString := AUsername;
        TempQry.Open;
        if not TempQry.IsEmpty then
          UserID := TempQry.FieldByName('id').AsInteger;
        TempQry.Close;
      finally
        TempQry.Free; // Безопасно освобождаем
      end;
    except
      on E: Exception do
      begin
        Log.Warn(Format('Неудачная попытка входа (ошибка БД): %s', [AUsername]));
        Result := TJSONObject.Create;
        Result.AddPair('status', 'error');
        Result.AddPair('message', 'Invalid username or password');
        Exit; // TempConn освободится в внешнем finally
      end;
    end;
  finally
    TempConn.Free; // Гарантированно закрываем временное соединение
  end;

  if UserID = 0 then
  begin
    Log.Warn(Format('Пользователь %s не найден в таблице users', [AUsername]));
    Result := TJSONObject.Create;
    Result.AddPair('status', 'error');
    Result.AddPair('message', 'Invalid username or password');
    Exit;
  end;

  // 2. Генерируем токен и сохраняем в БД, используя ОСНОВНОЙ PGConn (который теперь не тронут!)
  Token := TGUID.NewGuid.ToString;
  ExpirationTime := IncMinute(Now, 24 * 60);

  PGConn.StartTransaction;
  try
    qrySession.Close;
    qrySession.ParamByName('uid').AsInteger := UserID;
    qrySession.ParamByName('token').AsString := Token;
    qrySession.ParamByName('exp').AsDateTime := ExpirationTime;
    qrySession.ExecSQL;
    PGConn.Commit;

    Log.Info(Format('Успешный вход. Пользователь ID: %d, выдан токен.', [UserID]));

    Result := TJSONObject.Create;
    Result.AddPair('status', 'success');
    Result.AddPair('token', Token);
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
  AuthUserID: Integer;
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
      PGConn.Open;
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

          // Парсинг occurred_at
          OccurredAtStr := Item.GetValue<string>('occurred_at', '');
          if OccurredAtStr <> '' then
          begin
            if not TryISO8601ToDate(OccurredAtStr, OccurredAt) then
              OccurredAt := Now; // Fallback, если формат неверный
          end
          else
            OccurredAt := Now;

          // 🔑 ИСПРАВЛЕНИЕ 1: Используем AuthUserID из сессии, а не из JSON
          qryInsert.ParamByName('uid').AsInteger := AuthUserID;

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

