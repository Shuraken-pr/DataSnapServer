unit FormUnitMain;

interface

uses
  Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.AppEvnts, Vcl.StdCtrls, IdHTTPWebBrokerBridge, IdGlobal, Web.HTTPApp,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client,
  ServerSettings, frmServerSettings;

type
  TfrmServer = class(TForm)
    ButtonStart: TButton;
    ButtonStop: TButton;
    EditPort: TEdit;
    Label1: TLabel;
    ApplicationEvents1: TApplicationEvents;
    ButtonOpenBrowser: TButton;
    FDManager1: TFDManager;
    procedure FormCreate(Sender: TObject);
    procedure ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
    procedure ButtonOpenBrowserClick(Sender: TObject);
  private
    FServer: TIdHTTPWebBrokerBridge;
    procedure StartServer;
    procedure CheckAndLoadSettings;
    procedure ApplySettingsToManager(const Settings: TServerSettings);
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmServer: TfrmServer;

implementation

{$R *.dfm}

uses
{$IFDEF MSWINDOWS}
  WinApi.Windows, Winapi.ShellApi,
{$ENDIF}
  Datasnap.DSSession,
  System.Generics.Collections;

procedure TfrmServer.ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
begin
  ButtonStart.Enabled := not FServer.Active;
  ButtonStop.Enabled := FServer.Active;
  EditPort.Enabled := not FServer.Active;
end;

procedure TfrmServer.CheckAndLoadSettings;
var
  Settings: TServerSettings;
  NeedConfig: Boolean;
begin
  Settings := TServerSettings.Create;
  try
    // 1. Загружаем из файла
    NeedConfig := not Settings.LoadFromFile;

    // 2. Если файл загрузился, пробуем соединиться
    if not NeedConfig then
    begin
      // "Тихая" проверка соединения (без вывода ошибок пользователю)
      if not Settings.TestConnection then
        NeedConfig := True; // Соединение не удалось -> нужна форма
    end;

    // 3. Если нужна настройка (нет файла ИЛИ битые креды)
    if NeedConfig then
    begin
      Caption := 'Настройка сервера'; // Меняем заголовок окна
      if not TformServerSettings.Execute(Settings) then
      begin
        ShowMessage('Запуск сервера отменён: нет валидных настроек БД.');
        Halt(0); // Прерываем, если пользователь нажал "Отмена"
      end;
    end;

    // 4. Применяем в FDManager (теперь мы уверены, что Settings валидны)
    ApplySettingsToManager(Settings);

    Caption := 'DataSnap Server: ' + Settings.Database; // Возвращаем нормальный заголовок

  finally
    Settings.Free;
  end;
end;

procedure TfrmServer.ApplySettingsToManager(const Settings: TServerSettings);
var
  ConnDefName: string;
  ConnDef: IFDStanConnectionDef;
begin
  ConnDefName := 'PgServerConn';

  ConnDef := FDManager1.ConnectionDefs.FindConnectionDef(ConnDefName);
  if not Assigned(ConnDef) then
    ConnDef := FDManager1.ConnectionDefs.AddConnectionDef;

  with ConnDef do
  begin
    Name := ConnDefName;
    Params.DriverID := 'PG';
    Params.Database := Settings.Database;
    Params.UserName := Settings.Username;
    Params.Password := Settings.Password;
    Params.Values['Server'] := Settings.Host;
    Params.Values['Port'] := IntToStr(Settings.Port);
    Params.Pooled := True;
    Params.PoolMaximumItems := 10;
  end;

  FDManager1.Active := True;
end;

procedure TfrmServer.ButtonOpenBrowserClick(Sender: TObject);
{$IFDEF MSWINDOWS}
var
  LURL: string;
{$ENDIF}
begin
  StartServer;
{$IFDEF MSWINDOWS}
  LURL := Format('http://localhost:%s', [EditPort.Text]);
  ShellExecute(0,
        nil,
        PChar(LURL), nil, nil, SW_SHOWNOACTIVATE);
{$ENDIF}
end;

procedure TfrmServer.ButtonStartClick(Sender: TObject);
begin
  StartServer;
end;

procedure TerminateThreads;
begin
  if TDSSessionManager.Instance <> nil then
    TDSSessionManager.Instance.TerminateAllSessions;
end;

procedure TfrmServer.ButtonStopClick(Sender: TObject);
begin
  TerminateThreads;
  FServer.Active := False;
  FServer.Bindings.Clear;
end;

procedure TfrmServer.FormCreate(Sender: TObject);
begin
  FServer := TIdHTTPWebBrokerBridge.Create(Self);
  try
    CheckAndLoadSettings; // Проверяем конфигурацию ДО запуска сервера
  except
    on E: Exception do
    begin
      ShowMessage('Критическая ошибка запуска сервера:' + sLineBreak + E.Message);
      Halt(0); // ✅ Корректное завершение процесса до входа в цикл сообщений
    end;
  end;
end;

procedure TfrmServer.StartServer;
begin
  if not FServer.Active then
  begin
    FServer.Bindings.Clear;
    FServer.DefaultPort := StrToInt(EditPort.Text);
    FServer.Active := True;
  end;
end;

end.
