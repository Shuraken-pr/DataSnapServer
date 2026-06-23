unit RateLimiter;

interface

uses
  System.SysUtils, System.Generics.Collections,
  FireDAC.Comp.Client, FireDAC.Stan.Param;

type
  /// <summary>
  /// Результат проверки rate limit
  /// </summary>
  TRateLimitResult = (rlAllowed, rlExceeded);
  
  /// <summary>
  /// Rate limiter — ограничивает количество запросов по IP/endpoint
  /// </summary>
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
      'SET request_count = rate_limits.request_count + 1, ' +
      '    window_start = CURRENT_TIMESTAMP';
    Qry.ParamByName('ip').AsString := AIPAddress;
    Qry.ParamByName('endpoint').AsString := AEndpoint;
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
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT cleanup_rate_limits()';
    Qry.Open;
  finally
    Qry.Free;
  end;
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
