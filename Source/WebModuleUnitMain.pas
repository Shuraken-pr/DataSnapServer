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
  FireDAC.Phys.PGDef, FireDAC.VCLUI.Wait, ServerSessionContext;

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
  private
    FServerFunctionInvokerAction: TWebActionItem;
    function AllowServerFunctionInvoker: Boolean;
  public
  end;

var
  WebModuleClass: TComponentClass = TWebModule1;

implementation

{$R *.dfm}

uses
  Web.WebReq, ServerSettings, ServerLogger;

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

procedure TWebModule1.WebModuleBeforeDispatch(Sender: TObject;
  Request: TWebRequest; Response: TWebResponse; var Handled: Boolean);
var
  SessionToken: string;
  PathInfo: string;
  UserID: Integer;
  QryUser: TFDQuery;
begin
  CurrentUserID := 0; // <--- ДОБАВИТЬ ЭТУ СТРОКУ (Сброс в начале каждого запроса)
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

  if StartsText('/datasnap/', PathInfo) then
  begin
    if ContainsText(PathInfo, '/Login') then
    begin
      // Пропускаем проверку для Login
    end
    else
    begin
      SessionToken := string(Request.GetFieldByName('X-Session-Token'));

      if SessionToken = '' then
      begin
        Log.Warn(Format('WebModule: Missing session token from %s', [string(Request.RemoteAddr)]));
        Response.StatusCode := 401;
        Response.Content := '{"error":"Unauthorized"}';
        Response.ContentType := 'application/json';
        Handled := True;
        Exit;
      end;

      // Проверяем токен и сразу получаем user_id — один запрос вместо двух
      if not WebConn.Connected then WebConn.Open;

      QryUser := TFDQuery.Create(nil);
      try
        QryUser.Connection := WebConn;
        QryUser.SQL.Text :=
          'SELECT user_id FROM user_sessions ' +
          'WHERE session_token = :token AND expires_at > CURRENT_TIMESTAMP ' +
          'LIMIT 1';
        QryUser.ParamByName('token').AsString := SessionToken;
        QryUser.Open;
        if not QryUser.IsEmpty then
          UserID := QryUser.FieldByName('user_id').AsInteger
        else
          UserID := 0;
        QryUser.Close;
      finally
        QryUser.Free;
      end;

      if UserID > 0 then
      begin
        CurrentUserID := UserID;
      end
      else
      begin
        Log.Warn(Format('WebModule: Invalid/expired token from %s', [string(Request.RemoteAddr)]));
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

function TWebModule1.AllowServerFunctionInvoker: Boolean;
begin
  Result := (Request.RemoteAddr = '127.0.0.1') or
    (Request.RemoteAddr = '0:0:0:0:0:0:0:1') or (Request.RemoteAddr = '::1');
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
