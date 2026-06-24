unit SecurityAuditor;

interface

uses
  System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client, FireDAC.Stan.Param;

type
  /// <summary>
  /// Уровень серьёзности события безопасности
  /// </summary>
  TSecuritySeverity = (ssInfo, ssWarning, ssCritical);
  
  /// <summary>
  /// Запись события безопасности
  /// </summary>
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
  
  /// <summary>
  /// Аудитор безопасности — записывает события в таблицу security_events
  /// </summary>
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
  System.JSON, Data.DB;

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
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    
    Qry.SQL.Text := 
      'INSERT INTO security_events ' +
      '(event_type, username, ip_address, user_agent, details, severity) ' +
      'VALUES (:event_type, :username, :ip_address, :user_agent, ' +
      ':details, :severity)';
    
    // 🔑 Явно указываем типы параметров для избежания ошибок FireDAC
    Qry.ParamByName('event_type').DataType := ftWideString;
    Qry.ParamByName('username').DataType := ftWideString;
    Qry.ParamByName('ip_address').DataType := ftWideString;
    Qry.ParamByName('user_agent').DataType := ftWideString;
    // 🔑 details передаётся как строка, преобразуется в JSONB через to_jsonb() в SQL
    Qry.ParamByName('severity').DataType := ftWideString;
    
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
