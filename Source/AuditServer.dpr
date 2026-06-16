program AuditServer;
{$APPTYPE GUI}

{$R *.dres}

uses
  Vcl.Forms,
  Web.WebReq,
  IdHTTPWebBrokerBridge,
  FormUnitMain in 'FormUnitMain.pas' {frmServer},
  ServerMethodsUnitMain in 'ServerMethodsUnitMain.pas' {ServerMethods1: TDSServerModule},
  WebModuleUnitMain in 'WebModuleUnitMain.pas' {WebModule1: TWebModule},
  ServerSettings in 'ServerSettings.pas',
  WinDPAPIUtils in 'WinDPAPIUtils.pas',
  ServerLogger in 'ServerLogger.pas',
  ServerSessionContext in 'ServerSessionContext.pas';

{$R *.res}

begin
  if WebRequestHandler <> nil then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  Application.Initialize;
  Application.CreateForm(TfrmServer, frmServer);
  Application.Run;
end.
