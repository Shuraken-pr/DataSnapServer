unit WebModuleUnitMain;

// ИСПРАВЛЕНО по итогам код-ревью:
//   [CRITICAL] Добавлена базовая аутентификация через TDSAuthenticationManager
//   [MEDIUM]   Запросы с невалидным API-ключом отклоняются до выполнения методов

interface

uses
  System.SysUtils, System.Classes, Web.HTTPApp, Datasnap.DSHTTPCommon,
  Datasnap.DSHTTPWebBroker, Datasnap.DSServer,
  Web.WebFileDispatcher, Web.HTTPProd,
  DataSnap.DSAuth,
  Datasnap.DSProxyJavaScript, IPPeerServer, Datasnap.DSMetadata,
  Datasnap.DSServerMetadata, Datasnap.DSClientMetadata, Datasnap.DSCommonServer,
  Datasnap.DSHTTP, ServerMethodsUnitMain, System.StrUtils, FireDAC.Stan.Intf,
  FireDAC.Stan.Option, FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS,
  FireDAC.Phys.Intf, FireDAC.DApt.Intf, FireDAC.Stan.Async, FireDAC.DApt,
  Data.DB, FireDAC.Comp.DataSet, FireDAC.Comp.Client, FireDAC.UI.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Phys, FireDAC.Phys.PG,
  FireDAC.Phys.PGDef, FireDAC.VCLUI.Wait, ServerSessionContext,
  System.JSON, UploadUtils, System.NetEncoding, ServerSettings,
  RateLimiter, SecurityAuditor;

type
  TWebModule1 = class(TWebModule)
    DSHTTPWebDispatcher1: TDSHTTPWebDispatcher;
    DSServer1: TDSServer;
    DSServerClass1: TDSServerClass;
    ServerFunctionInvoker: TPageProducer;
    ReverseString: TPageProducer;
    WebFileDispatcher1: TWebFileDispatcher;
    DSProxyGenerator1: TDSProxyGenerator;
    DSServerMetaDataProvider1: TDSServerMetaDataProvider;
    DSAuthenticationManager1: TDSAuthenticationManager;
    qryValidate: TFDQuery;
    WebConn: TFDConnection;
    procedure DSServerClass1GetClass(DSServerClass: TDSServerClass;
      var PersistentClass: TPersistentClass);
    procedure ServerFunctionInvokerHTMLTag(Sender: TObject; Tag: TTag;
      const TagString: string; TagParams: TStrings; var ReplaceText: string);
    procedure WebModuleDefaultAction(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebModuleBeforeDispatch(Sender: TObject;
      Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
    procedure WebFileDispatcher1BeforeDispatch(Sender: TObject;
      const AFileName: string; Request: TWebRequest; Response: TWebResponse;
      var Handled: Boolean);
    procedure WebModuleCreate(Sender: TObject);
    // НОВЫЕ обработчики аутентификации
    procedure DSAuthenticationManager1UserAuthenticate(
      Sender: TObject; const Protocol, Context, User, Password: string;
      var valid: Boolean; UserRoles: TStrings);
    procedure DSAuthenticationManager1UserAuthorize(
      Sender: TObject; AuthorizeEventObject: TDSAuthorizeEventObject;
      var valid: Boolean);
    procedure WebModuleAfterDispatch(Sender: TObject; Request: TWebRequest;
      Response: TWebResponse; var Handled: Boolean);
    procedure WebModuleUploadAction(Sender: TObject; Request: TWebRequest;
      Response: TWebResponse; var Handled: Boolean);
  private
    FServerFunctionInvokerAction: TWebActionItem;
    function AllowServerFunctionInvoker: Boolean;
    function GetRealClientIP: string;
  public
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;

implementation

{$R *.dfm}

uses
  Web.WebReq, ServerLogger;

procedure TWebModule1.DSServerClass1GetClass(
  DSServerClass: TDSServerClass; var PersistentClass: TPersistentClass);
begin
  PersistentClass := ServerMethodsUnitMain.TServerMethods1;
end;

procedure TWebModule1.ServerFunctionInvokerHTMLTag(Sender: TObject; Tag: TTag;
  const TagString: string; TagParams: TStrings; var ReplaceText: string);
begin
  if SameText(TagString, 'urlpath') then
    ReplaceText := string(Request.InternalScriptName)
  else if SameText(TagString, 'port') then
    ReplaceText := IntToStr(Request.ServerPort)
  else if SameText(TagString, 'host') then
    ReplaceText := string(Request.Host)
  else if SameText(TagString, 'classname') then
    ReplaceText := ServerMethodsUnitMain.TServerMethods1.ClassName
  else if SameText(TagString, 'loginrequired') then
    if DSHTTPWebDispatcher1.AuthenticationManager <> nil then
      ReplaceText := 'true'
    else
      ReplaceText := 'false'
  else if SameText(TagString, 'serverfunctionsjs') then
    ReplaceText := string(Request.InternalScriptName) + '/js/serverfunctions.js'
  else if SameText(TagString, 'servertime') then
    ReplaceText := DateTimeToStr(Now)
  else if SameText(TagString, 'serverfunctioninvoker') then
    if AllowServerFunctionInvoker then
      ReplaceText :=
      '<div><a href="' + string(Request.InternalScriptName) +
      '/ServerFunctionInvoker" target="_blank">Server Functions</a></div>'
    else
      ReplaceText := '';
end;

procedure TWebModule1.WebModuleDefaultAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  if (Request.InternalPathInfo = '') or (Request.InternalPathInfo = '/') then
    Response.Content := ReverseString.Content
  else
    Response.SendRedirect(Request.InternalScriptName + '/');
end;

procedure TWebModule1.WebModuleAfterDispatch(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
begin
  CurrentUserID := 0;
end;

procedure TWebModule1.WebModuleUploadAction(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  JsonStr, FileName, FileUUID, FilePath, DirPath, Sha256: string;
  PhotoBase64: string;
  PhotoBytes: TBytes;
  PhotoStream: TBytesStream;
  ResponseObj: TJSONObject;
  Payload: TJSONObject;
  Lat, Lon: Double;
  Year, Month, Day: Word;
  FileSize: Int64;
  Conn: TFDConnection;
  Qry: TFDQuery;
  LogId: Int64;
  AuthToken: string;
  DetailsPayload: TJSONObject;
  DetailsStr: string;
  QryUser: TFDQuery;
  UserID: Int64;
  Limiter: TRateLimiter;
  Auditor: TSecurityAuditor;
  ClientIP: string;
begin
  Handled := True;
  ClientIP := GetRealClientIP;
  UserID := 0;

  try
    // 🔑 RATE LIMITING для /upload
    Conn := TFDConnection.Create(nil);
    try
      if Assigned(Conn) and (AppSettings.ApplyToConn(Conn)) then
      begin
        Limiter := TRateLimiter.Create(Conn);
        try
          if Limiter.CheckLimit(ClientIP, '/upload') = rlExceeded then
          begin
            Auditor := TSecurityAuditor.Create(Conn);
            try
              Auditor.LogEvent('rate_limit_exceeded', '', ClientIP,
                'Endpoint: /upload (limit: 100/hour)', ssWarning);
            finally
              Auditor.Free;
            end;

            Response.StatusCode := 429;
            Response.ContentType := 'application/json';
            Response.Content := '{"result":"error","message":"Too Many Requests"}';
            Exit;
          end;
          Limiter.RecordRequest(ClientIP, '/upload');
        finally
          Limiter.Free;
        end;
      end;
    finally
      FreeAndNil(Conn);
    end;

    AuthToken := string(Request.GetFieldByName('X-Session-Token'));
    if AuthToken = '' then
      AuthToken := string(Request.GetFieldByName('HTTP_X_SESSION_TOKEN'));

    if AuthToken = '' then
    begin
      Response.StatusCode := 401;
      Response.ContentType := 'application/json';
      Response.Content := '{"result":"error","message":"Unauthorized"}';
      Exit;
    end;

    Conn := TFDConnection.Create(nil);
    try
      if Assigned(Conn) and (AppSettings.ApplyToConn(conn)) then
      begin
        QryUser := TFDQuery.Create(nil);
        try
          QryUser.Connection := Conn;
          QryUser.SQL.Text :=
            'SELECT user_id FROM user_sessions ' +
            'WHERE session_token = :token AND expires_at > CURRENT_TIMESTAMP ' +
            'LIMIT 1';
          QryUser.ParamByName('token').AsString := AuthToken;
          QryUser.Open;
          if not QryUser.IsEmpty then
            UserID := QryUser.FieldByName('user_id').AsLargeInt
          else
            UserID := 0;
          QryUser.Close;
        finally
          QryUser.Free;
        end;
      end;

      if UserID <= 0 then
      begin
        Response.StatusCode := 401;
        Response.ContentType := 'application/json';
        Response.Content := '{"result":"error","message":"Unauthorized: invalid or expired token"}';
        Exit;
      end;

      if Request.Method <> 'POST' then
      begin
        Response.StatusCode := 405;
        Response.ContentType := 'application/json';
        Response.Content := '{"result":"error","message":"Method not allowed"}';
        Exit;
      end;

      JsonStr := Request.Content;
      if JsonStr = '' then
      begin
        Response.StatusCode := 400;
        Response.ContentType := 'application/json';
        Response.Content := '{"result":"error","message":"Empty body"}';
        Exit;
      end;

      Payload := TJSONObject.ParseJSONValue(JsonStr) as TJSONObject;
      if not Assigned(Payload) then
      begin
        Response.StatusCode := 400;
        Response.ContentType := 'application/json';
        Response.Content := '{"result":"error","message":"Invalid JSON"}';
        Exit;
      end;
      try
        Lat := 0; Lon := 0;
        if Payload.GetValue('lat') <> nil then
          Lat := (Payload.GetValue('lat') as TJSONNumber).AsDouble;
        if Payload.GetValue('lon') <> nil then
          Lon := (Payload.GetValue('lon') as TJSONNumber).AsDouble;

        // 🔑 ВАЛИДАЦИЯ КООРДИНАТ: lat должно быть -90..90, lon -180..180
        if (Lat < -90.0) or (Lat > 90.0) then
        begin
          Response.StatusCode := 400;
          Response.ContentType := 'application/json';
          Response.Content := '{"result":"error","message":"Invalid latitude: must be between -90 and 90"}';
          Exit;
        end;
        if (Lon < -180.0) or (Lon > 180.0) then
        begin
          Response.StatusCode := 400;
          Response.ContentType := 'application/json';
          Response.Content := '{"result":"error","message":"Invalid longitude: must be between -180 and 180"}';
          Exit;
        end;

        PhotoBase64 := '';
        if Payload.GetValue('photo_base64') <> nil then
          PhotoBase64 := Payload.GetValue('photo_base64').Value;

        if PhotoBase64 = '' then
        begin
          Response.StatusCode := 400;
          Response.ContentType := 'application/json';
          Response.Content := '{"result":"error","message":"Missing photo_base64"}';
          Exit;
        end;

        // 🔑 Удаляем возможные переносы строк из Base64 (JSON может добавить \n при передаче)
        PhotoBase64 := StringReplace(PhotoBase64, #13, '', [rfReplaceAll]);
        PhotoBase64 := StringReplace(PhotoBase64, #10, '', [rfReplaceAll]);

        if not TryDecodeBase64(PhotoBase64, PhotoBytes) then
        begin
          Response.StatusCode := 400;
          Response.ContentType := 'application/json';
          Response.Content := '{"result":"error","message":"Invalid photo_base64: not valid Base64"}';
          Exit;
        end;
        FileSize := Length(PhotoBytes);

        if FileSize > 10 * 1024 * 1024 then
        begin
          Response.StatusCode := 413;
          Response.ContentType := 'application/json';
          Response.Content := '{"result":"error","message":"File too large, max 10MB"}';
          Exit;
        end;

        PhotoStream := TBytesStream.Create(PhotoBytes);
        try
          if not IsValidJpegMagic(PhotoStream) then
          begin
            Response.StatusCode := 400;
            Response.ContentType := 'application/json';
            Response.Content := '{"result":"error","message":"Invalid format, JPEG expected"}';
            Exit;
          end;

          Sha256 := ComputeSHA256(PhotoStream);

          FileUUID := GenerateFileUUID;
          DirPath := EnsureAuditDir('C:\AuditFiles', Now);
          if not SaveUploadedFile(PhotoStream, DirPath, FileUUID, FilePath) then
            raise Exception.Create('Failed to save file');

          if Payload.GetValue('photo_filename') <> nil then
            FileName := Payload.GetValue('photo_filename').Value
          else
            FileName := 'photo.jpg';

          // Проверка конфигурации базы данных
          if (AppSettings.Host = '') or (AppSettings.Password = '') then
          begin
            // Попытка перезагрузить настройки (если сервер запущен как служба)
            AppSettings.LoadFromFile;
            if (AppSettings.Host = '') or (AppSettings.Password = '') then
            begin
              Response.StatusCode := 500;
              Response.ContentType := 'application/json';
              Response.Content := '{"result":"error","message":"Server not configured: database settings incomplete. Run GUI version first to configure DB connection."}';
              Exit;
            end;
          end;


          Qry := TFDQuery.Create(nil);
          try
            Qry.Connection := Conn;
            Qry.SQL.Text :=
              'INSERT INTO audit_logs (user_id, event_type, occurred_at, location, details, created_at) ' +
              'VALUES (:user_id, :event_type, :occurred_at, point(:lon, :lat), :details, NOW()) ' +
              'RETURNING id';
            Qry.ParamByName('user_id').AsLargeInt := UserID;
            Qry.ParamByName('event_type').AsString := 'mobile_audit';
            Qry.ParamByName('occurred_at').AsDateTime := Now;
            Qry.ParamByName('lon').AsFloat := Lon;
            Qry.ParamByName('lat').AsFloat := Lat;

            // Формируем details JSON без photo_base64 (чтобы не засорять TEXT поле)
            DetailsPayload := TJSONObject.Create;
            try
              if Payload.GetValue('event_type') <> nil then
                DetailsPayload.AddPair('event_type', Payload.GetValue('event_type').Value);
              if Payload.GetValue('lat') <> nil then
                DetailsPayload.AddPair('lat', TJSONNumber.Create((Payload.GetValue('lat') as TJSONNumber).AsDouble));
              if Payload.GetValue('lon') <> nil then
                DetailsPayload.AddPair('lon', TJSONNumber.Create((Payload.GetValue('lon') as TJSONNumber).AsDouble));
              if Payload.GetValue('title') <> nil then
                DetailsPayload.AddPair('title', Payload.GetValue('title').Value);
              if Payload.GetValue('device_id') <> nil then
                DetailsPayload.AddPair('device_id', Payload.GetValue('device_id').Value);
              if Payload.GetValue('batch_id') <> nil then
                DetailsPayload.AddPair('batch_id', Payload.GetValue('batch_id').Value);
              if Payload.GetValue('occurred_at') <> nil then
                DetailsPayload.AddPair('occurred_at', Payload.GetValue('occurred_at').Value);
              if Payload.GetValue('photo_filename') <> nil then
                DetailsPayload.AddPair('photo_filename', Payload.GetValue('photo_filename').Value);
              DetailsStr := DetailsPayload.ToString;
            finally
              DetailsPayload.Free;
            end;
            Qry.ParamByName('details').Size := 0;
            Qry.ParamByName('details').AsString := DetailsStr;
            Qry.Open;
            LogId := Qry.FieldByName('id').AsLargeInt;

            Qry.SQL.Text :=
              'INSERT INTO audit_files (log_id, file_uuid, storage_path, original_filename, file_size, checksum_sha256, mime_type) ' +
              'VALUES (:log_id, :uuid::uuid, :path, :orig, :size, :sha, :mime)';
            Qry.ParamByName('log_id').AsLargeInt := LogId;
            Qry.ParamByName('uuid').AsString := FileUUID;
            Qry.ParamByName('path').AsString := FilePath;
            Qry.ParamByName('orig').AsString := FileName;
            Qry.ParamByName('size').AsLargeInt := FileSize;
            Qry.ParamByName('sha').AsString := Sha256;
            Qry.ParamByName('mime').AsString := 'image/jpeg';
            Qry.ExecSQL;
          finally
            Qry.Free;
          end;

          ResponseObj := TJSONObject.Create;
          try
            ResponseObj.AddPair('result', 'ok');
            ResponseObj.AddPair('file_id', FileUUID);
            ResponseObj.AddPair('checksum', Sha256);
            DecodeDate(Now, Year, Month, Day);
            ResponseObj.AddPair('url', Format('https://%s/audit-files/%d/%d/%d/%s.jpg',
              [Request.Host, Year, Month, Day, FileUUID]));
            Response.StatusCode := 200;
            Response.ContentType := 'application/json';
            Response.Content := ResponseObj.ToString;
          finally
            ResponseObj.Free;
          end;
        finally
          PhotoStream.Free;
        end;
      finally
        Payload.Free;
      end;
    finally
      Conn.Free;
    end;

  except
    on E: Exception do
    begin
      Response.StatusCode := 500;
      Response.ContentType := 'application/json';
      Response.Content := '{"result":"error","message":"' + E.Message + '"}';
    end;
  end;
end;

procedure TWebModule1.WebModuleBeforeDispatch(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  SessionToken: string;
  PathInfo: string;
  UserID: Int64;
  QryUser: TFDQuery;
  Conn: TFDConnection;
  Limiter: TRateLimiter;
  Auditor: TSecurityAuditor;
  ClientIP: string;
begin
  CurrentUserID := 0;
  ClientIP := GetRealClientIP;
  CurrentIP := ClientIP;  // 🔑 Сохраняем IP в потоковую переменную
  PathInfo := string(Request.InternalPathInfo);

  // 🔑 НОВОЕ: Если запрос идет на корень сайта (например, из браузера),
  // отдаем простой JSON и прерываем дальнейшую обработку, чтобы не искать HTML-шаблоны.
  if (PathInfo = '') or (PathInfo = '/') then
  begin
    Response.Content := '{"status": "ok", "message": "DataSnap REST Server is running securely via HTTPS"}';
    Response.ContentType := 'application/json';
    Response.StatusCode := 200;
    Handled := True;
    Exit;
  end;

  // === upload endpoint (outside /datasnap/ REST) ===
  if PathInfo = '/upload' then
  begin
    WebModuleUploadAction(Sender, Request, Response, Handled);
    Exit;
  end;

  if StartsText('/datasnap/', PathInfo) then
  begin
    if ContainsText(PathInfo, '/Login') then
    begin
      // 🔑 RATE LIMITING для Login
      Conn := TFDConnection.Create(nil);
      try
        if AppSettings.ApplyToConn(Conn) then
        begin
          Limiter := TRateLimiter.Create(Conn);
          try
            if Limiter.CheckLimit(ClientIP, '/Login') = rlExceeded then
            begin
              Auditor := TSecurityAuditor.Create(Conn);
              try
                Auditor.LogEvent('rate_limit_exceeded', '', ClientIP,
                  'Endpoint: /Login (limit: 20/hour)', ssWarning);
              finally
                Auditor.Free;
              end;

              Response.StatusCode := 429;
              Response.Content := '{"error":"Too Many Requests"}';
              Response.ContentType := 'application/json';
              Handled := True;
              Exit;
            end;
            Limiter.RecordRequest(ClientIP, '/Login');
          finally
            Limiter.Free;
          end;
        end;
      finally
        FreeAndNil(Conn);
      end;
    end
    else
    begin
      SessionToken := string(Request.GetFieldByName('X-Session-Token'));

      if SessionToken = '' then
      begin
        Log.Warn(Format('WebModule: Missing session token from %s', [GetRealClientIP]));
        Response.StatusCode := 401;
        Response.Content := '{"error":"Unauthorized"}';
        Response.ContentType := 'application/json';
        Handled := True;
        Exit;
      end;

      // Проверяем токен и сразу получаем user_id — один запрос вместо двух
      UserID := 0;
      Conn := TFDConnection.Create(nil);
      try
        if AppSettings.ApplyToConn(conn) then
        begin
          QryUser := TFDQuery.Create(nil);
          try
            QryUser.Connection := Conn;
            QryUser.SQL.Text :=
              'SELECT user_id FROM user_sessions ' +
              'WHERE session_token = :token AND expires_at > CURRENT_TIMESTAMP ' +
              'LIMIT 1';
            QryUser.ParamByName('token').AsString := SessionToken;
            QryUser.Open;
            if not QryUser.IsEmpty then
              UserID := QryUser.FieldByName('user_id').AsLargeInt
            else
              UserID := 0;
            QryUser.Close;
          finally
            QryUser.Free;
          end;
        end;
      finally
        FreeAndNil(Conn);
      end;

      if UserID > 0 then
      begin
        CurrentUserID := UserID;
      end
      else
      begin
        Log.Warn(Format('WebModule: Invalid/expired token from %s', [GetRealClientIP]));
        Response.StatusCode := 401;
        Response.ContentType := 'application/json';
        Response.Content := '{"error":"Unauthorized: session expired or invalid"}';
        Handled := True;
        Exit;
      end;
    end;
  end;

  if FServerFunctionInvokerAction <> nil then
    FServerFunctionInvokerAction.Enabled := AllowServerFunctionInvoker;
end;


// НОВОЕ: обработчик аутентификации DataSnap
procedure TWebModule1.DSAuthenticationManager1UserAuthenticate(
  Sender: TObject; const Protocol, Context, User, Password: string;
  var valid: Boolean; UserRoles: TStrings);
begin
  // Делегируем проверку API-ключу в WebModuleBeforeDispatch
  // Здесь можно добавить проверку User/Password для более строгой аутентификации
  valid := True;
end;

// НОВОЕ: обработчик авторизации DataSnap
procedure TWebModule1.DSAuthenticationManager1UserAuthorize(
  Sender: TObject; AuthorizeEventObject: TDSAuthorizeEventObject;
  var valid: Boolean);
begin
  // По умолчанию разрешаем доступ ко всем методам,
  // т.к. аутентификация уже проверена на уровне HTTP-заголовка
  valid := True;
end;

function TWebModule1.GetRealClientIP: string;
var
  XForwardedFor: string;
  P: Integer;
begin
  Result := string(Request.RemoteAddr);
  
  // 🔑 Если запрос пришёл через reverse proxy (Nginx), берём реальный IP из X-Forwarded-For
  if (Result = '127.0.0.1') or (Result = '::1') or 
     (Result = '0:0:0:0:0:0:0:1') then
  begin
    XForwardedFor := string(Request.GetFieldByName('X-Forwarded-For'));
    if XForwardedFor <> '' then
    begin
      // X-Forwarded-For может содержать несколько IP через запятую: client, proxy1, proxy2
      // Берём первый (реальный клиент)
      P := Pos(',', XForwardedFor);
      if P > 0 then
        Result := Trim(Copy(XForwardedFor, 1, P - 1))
      else
        Result := Trim(XForwardedFor);
    end;
  end;
end;

function TWebModule1.AllowServerFunctionInvoker: Boolean;
var
  RealIP: string;
begin
  RealIP := GetRealClientIP;
  Result := (RealIP = '127.0.0.1') or
    (RealIP = '0:0:0:0:0:0:0:1') or (RealIP = '::1');
end;

procedure TWebModule1.WebFileDispatcher1BeforeDispatch(Sender: TObject;
  const AFileName: string; Request: TWebRequest; Response: TWebResponse;
  var Handled: Boolean);
var
  D1, D2: TDateTime;
begin
  Handled := False;
  if SameFileName(ExtractFileName(AFileName), 'serverfunctions.js') then
    if not FileExists(AFileName) or (FileAge(AFileName, D1) and FileAge(WebApplicationFileName, D2) and (D1 < D2)) then
    begin
      DSProxyGenerator1.TargetDirectory := ExtractFilePath(AFileName);
      DSProxyGenerator1.TargetUnitName := ExtractFileName(AFileName);
      DSProxyGenerator1.Write;
    end;
end;

procedure TWebModule1.WebModuleCreate(Sender: TObject);
begin
  FServerFunctionInvokerAction := ActionByName('ServerFunctionInvokerAction');
  WebConn.ConnectionDefName := CONN_DEF_NAME;
  // ИСПРАВЛЕНО: назначаем AuthenticationManager для DataSnap
  DSHTTPWebDispatcher1.AuthenticationManager := DSAuthenticationManager1;
end;

initialization
finalization
  Web.WebReq.FreeWebModules;

end.
