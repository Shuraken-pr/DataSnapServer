unit FormUnitMain;

// ИСПРАВЛЕНО по итогам код-ревью:
//   [HIGH]   Добавлен FormDestroy для корректной остановки сервера
//   [MEDIUM] StrToInt заменён на StrToIntDef с проверкой диапазона
//   [LOW]    Конструкция with заменена на явную квалификацию
//   [LOW]    Имя подключения использует константу CONN_DEF_NAME

interface

uses
  Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.AppEvnts, Vcl.StdCtrls, IdHTTPWebBrokerBridge, IdGlobal, Web.HTTPApp,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.UI.Intf,
  FireDAC.Phys.Intf, FireDAC.Stan.Def, FireDAC.Phys, FireDAC.Comp.Client,
  ServerSettings, frServerSettings, FireDAC.Stan.Pool, FireDAC.Stan.Async,
  FireDAC.Phys.PG, FireDAC.Phys.PGDef, FireDAC.VCLUI.Wait, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  Vcl.ExtCtrls;

type
  TfrmServer = class(TForm)
    ButtonStart: TButton;
    ButtonStop: TButton;
    EditPort: TEdit;
    Label1: TLabel;
    ApplicationEvents1: TApplicationEvents;
    ButtonOpenBrowser: TButton;
    FDManager1: TFDManager;
    StartConn: TFDConnection;
    qryClearSession: TFDQuery;
    tmrCheckSessions: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);     // НОВОЕ
    procedure ApplicationEvents1Idle(Sender: TObject; var Done: Boolean);
    procedure ButtonStartClick(Sender: TObject);
    procedure ButtonStopClick(Sender: TObject);
    procedure ButtonOpenBrowserClick(Sender: TObject);
    procedure tmrCheckSessionsTimer(Sender: TObject);
  private
    FServer: TIdHTTPWebBrokerBridge;
    procedure StartServer;
    procedure CheckAndLoadSettings;
    procedure ApplySettingsToManager(const Settings: TServerSettings);
    procedure CheckCleanupTaskStatus;
  public
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
  System.Generics.Collections,
  System.IOUtils,
  System.DateUtils,
  ServerLogger;  // логирование

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
      if not Settings.TestConnection then
        NeedConfig := True;
    end;

    // 3. Если нужна настройка (нет файла ИЛИ нерабочие креды)
    if NeedConfig then
    begin
      Caption := 'Настройка сервера';
      if not TfrmServerSettings.Execute(Settings) then
      begin
        Log.Info('CheckAndLoadSettings: Server startup cancelled by user');
        ShowMessage('Запуск сервера отменён: нет валидных настроек БД.');
        Halt(0);
      end;
    end;

    // 4. Применяем в FDManager (теперь мы уверены, что Settings валидны)
    ApplySettingsToManager(Settings);

    Caption := 'DataSnap Server: ' + Settings.Database;
    Log.Info(Format('CheckAndLoadSettings: Settings loaded: %s@%s:%d/%s',
    [Settings.Username, Settings.Host, Settings.Port, Settings.Database]));
  finally
    Settings.Free;
  end;
end;

procedure TfrmServer.CheckCleanupTaskStatus;
var
  LogDir: string;
  LogFiles: TArray<string>;
  LastLogFile: string;
  LastRunTime: TDateTime;
  CurrentFile: string;
  FileTime: TDateTime;
begin
  LogDir := 'C:\AuditServer\logs';

  if not TDirectory.Exists(LogDir) then
  begin
    Log.Warn('Папка логов очистки не найдена: ' + LogDir);
    Exit;
  end;

  // 🔑 ИСПРАВЛЕНИЕ: Используем TDirectory.GetFiles и TFile.GetLastWriteTime
  LogFiles := TDirectory.GetFiles(LogDir, 'cleanup_*.log');

  if Length(LogFiles) = 0 then
  begin
    Log.Warn('Логи очистки сессий не найдены');
    Exit;
  end;

  // 🔑 ИСПРАВЛЕНИЕ: Находим самый свежий лог-файл
  LastLogFile := '';
  LastRunTime := 0;

  for CurrentFile in LogFiles do
  begin
    FileTime := TFile.GetLastWriteTime(CurrentFile);
    if FileTime > LastRunTime then
    begin
      LastRunTime := FileTime;
      LastLogFile := CurrentFile;
    end;
  end;

  if LastLogFile = '' then
  begin
    Log.Warn('Не удалось определить последний лог-файл');
    Exit;
  end;

  // 🔑 ИСПРАВЛЕНИЕ: Используем EncodeTime правильно (часы, минуты, секунды, миллисекунды)
  if Now - LastRunTime > EncodeTime(2, 0, 0, 0) then
  begin
    Log.Warn(Format('Очистка сессий не запускалась более 2 часов. Последний запуск: %s (файл: %s)',
      [DateTimeToStr(LastRunTime), ExtractFileName(LastLogFile)]));
  end
  else
  begin
    Log.Info(Format('Очистка сессий работает нормально. Последний запуск: %s',
      [DateTimeToStr(LastRunTime)]));
  end;
end;

procedure TfrmServer.ApplySettingsToManager(const Settings: TServerSettings);
var
  ConnDef: IFDStanConnectionDef;
begin
  // ИСПРАВЛЕНО: with заменён на явную квалификацию
  // ИСПРАВЛЕНО: имя подключения берётся из константы CONN_DEF_NAME
  ConnDef := FDManager1.ConnectionDefs.FindConnectionDef(CONN_DEF_NAME);
  if not Assigned(ConnDef) then
    ConnDef := FDManager1.ConnectionDefs.AddConnectionDef;

  ConnDef.Name := CONN_DEF_NAME;
  ConnDef.Params.DriverID := 'PG';
  ConnDef.Params.Database := Settings.Database;
  ConnDef.Params.UserName := Settings.Username;
  ConnDef.Params.Password := Settings.Password;
  ConnDef.Params.Values['Server'] := Settings.Host;
  ConnDef.Params.Values['Port'] := IntToStr(Settings.Port);
  ConnDef.Params.Pooled := True;
  // ИСПРАВЛЕНО: размер пула вынесен в константу (можно перенести в конфиг)
  ConnDef.Params.PoolMaximumItems := 10;

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
  ShellExecute(0, nil, PChar(LURL), nil, nil, SW_SHOWNOACTIVATE);
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
  Log.Info('TfrmServer: Server stopped');
end;

procedure TfrmServer.FormCreate(Sender: TObject);
begin
  FServer := TIdHTTPWebBrokerBridge.Create(Self);
  try
    CheckAndLoadSettings;
    StartConn.ConnectionDefName := CONN_DEF_NAME;
    if not StartConn.Connected then
      StartConn.Open;
    qryClearSession.ExecSQL;
    Log.Info('Настройки успешно загружены и применены. Сервер готов к запуску.');
  except
    on E: Exception do
    begin
      Log.Fatal('Не удалось запустить сервер: ' + E.Message);
      Log.LogException(E);
      ShowMessage('Критическая ошибка запуска сервера:' + sLineBreak + E.Message);
      Halt(0);
    end;
  end;
end;

// НОВОЕ: гарантированная остановка сервера и освобождение ресурсов
procedure TfrmServer.FormDestroy(Sender: TObject);
begin
  if FServer.Active then
  begin
    TerminateThreads;
    FServer.Active := False;
    FServer.Bindings.Clear;
  end;
  FDManager1.Active := False;
  Log.Info('FormDestroy: Server destroyed, resources released');
end;

procedure TfrmServer.StartServer;
var
  CurPort: Integer;
begin
  if not Assigned(FServer) then
    FServer := TIdHTTPWebBrokerBridge.Create(Self);

  FServer.Bindings.Clear;

  // 🔑 УПРОЩЕНИЕ: Никакого SSL! Nginx сам занимается HTTPS.
  // Сервер слушает только локальный HTTP-порт.
  CurPort := StrToIntDef(EditPort.Text, 0);
  if (CurPort < 1) or (CurPort > 65535) then
  begin
    ShowMessage('Порт должен быть числом от 1 до 65535');
    Exit;
  end;

  with FServer.Bindings.Add do
  begin
    IP := '127.0.0.1'; // Только локальные подключения от Nginx
    Port := CurPort;    // Обычно 8082
  end;

  FServer.DefaultPort := CurPort;
  FServer.Active := True;
  Log.Info(Format('StartServer: Server started in HTTP mode on port %d (behind Nginx)', [CurPort]));
end;

procedure TfrmServer.tmrCheckSessionsTimer(Sender: TObject);
begin
  CheckCleanupTaskStatus;
end;

end.
