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
  frmServerSettings in 'frmServerSettings.pas' {formServerSettings};

{$R *.res}

begin
  if WebRequestHandler <> nil then
    WebRequestHandler.WebModuleClass := WebModuleClass;
  Application.Initialize;
  Application.CreateForm(TfrmServer, frmServer);
  Application.Run;
end.
