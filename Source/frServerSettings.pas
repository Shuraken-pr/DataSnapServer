unit frServerSettings;

// ИСПРАВЛЕНО по итогам код-ревью:
//   [MEDIUM] Устранён двойной вызов ApplyFormToSettings
//   [MEDIUM] FTestPassed сбрасывается при изменении любого поля
//   [LOW]    Удалена неиспользуемая глобальная переменная formServerSettings
//   [LOW]    Единообразное именование: TfrmServerSettings вместо TformServerSettings

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, cxGraphics, cxControls, cxLookAndFeels,
  cxLookAndFeelPainters, cxContainer, cxEdit, dxLayoutcxEditAdapters,
  dxLayoutControlAdapters, dxLayoutContainer, cxClasses, Vcl.StdCtrls,
  Vcl.Samples.Spin, Vcl.Buttons, cxTextEdit, cxMaskEdit, cxSpinEdit,
  dxLayoutControl, ServerSettings, System.UITypes;

type
  TfrmServerSettings = class(TForm)
    lcConnectionSettings: TdxLayoutControl;
    edPort: TcxSpinEdit;
    edPassword: TcxTextEdit;
    btnOk: TBitBtn;
    edLogin: TcxTextEdit;
    edDatabase: TcxTextEdit;
    edServer: TcxTextEdit;
    lcConnectionSettingsGroup_Root: TdxLayoutGroup;
    liPort: TdxLayoutItem;
    liPassword: TdxLayoutItem;
    lgAction: TdxLayoutGroup;
    liOk: TdxLayoutItem;
    liLogin: TdxLayoutItem;
    liDatabase: TdxLayoutItem;
    liServer: TdxLayoutItem;
    btnTest: TButton;
    liTest: TdxLayoutItem;
    edApiKey: TcxTextEdit;
    liApiKey: TdxLayoutItem;
    btnGenerateApiKey: TButton;
    dxLayoutItem1: TdxLayoutItem;
    procedure btnOkClick(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
    // НОВОЕ: обработчики OnChange для сброса флага теста
    procedure FieldChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnGenerateApiKeyClick(Sender: TObject);
  private
    FSettings: TServerSettings;
    FTestPassed: Boolean;
    function ValidateInput: Boolean;
    /// <summary>Копирует данные формы в указанный объект TServerSettings</summary>
    procedure ApplyFormTo(ASettings: TServerSettings);
  public
    class function Execute(ASettings: TServerSettings): Boolean;
  end;

// ИСПРАВЛЕНО: удалена неиспользуемая глобальная переменная formServerSettings

implementation

{$R *.dfm}

uses
  ServerLogger; // логирование

class function TfrmServerSettings.Execute(ASettings: TServerSettings): Boolean;
var
  frm: TfrmServerSettings;
begin
  frm := TfrmServerSettings.Create(nil);
  try
    frm.FSettings := ASettings;
    // Заполняем поля из настроек
    frm.edServer.Text := ASettings.Host;
    frm.edPort.Text := IntToStr(ASettings.Port);
    frm.edDatabase.Text := ASettings.Database;
    frm.edLogin.Text := ASettings.Username;
    frm.edPassword.Text := ASettings.Password;
    frm.FTestPassed := False;

    Result := (frm.ShowModal = mrOk);
  finally
    frm.Free;
  end;
end;

procedure TfrmServerSettings.FormCreate(Sender: TObject);
begin
  // ИСПРАВЛЕНО: подписываем все поля на OnChange для сброса FTestPassed
  edServer.Properties.OnChange := FieldChange;
  edPort.Properties.OnChange := FieldChange;
  edDatabase.Properties.OnChange := FieldChange;
  edLogin.Properties.OnChange := FieldChange;
  edPassword.Properties.OnChange := FieldChange;
end;

// ИСПРАВЛЕНО: при любом изменении полей — сбрасываем флаг пройденного теста,
// чтобы пользователь не мог сохранить настройки, изменённые после теста
procedure TfrmServerSettings.FieldChange(Sender: TObject);
begin
  FTestPassed := False;
end;

// ИСПРАВЛЕНО: метод теперь принимает целевой объект параметром,
// а не пишет в FSettings напрямую
procedure TfrmServerSettings.ApplyFormTo(ASettings: TServerSettings);
begin
  ASettings.Host := Trim(edServer.Text);
  ASettings.Port := StrToIntDef(edPort.Text, 5432);
  ASettings.Database := Trim(edDatabase.Text);
  ASettings.Username := Trim(edLogin.Text);
  ASettings.Password := edPassword.Text;
  ASettings.ApiKey := edApiKey.Text;
end;

procedure TfrmServerSettings.btnTestClick(Sender: TObject);
var
  TempSettings: TServerSettings;
begin
  if not ValidateInput then Exit;

  // ИСПРАВЛЕНО: применяем данные формы к ВРЕМЕННОМУ объекту,
  // не затрагивая FSettings
  TempSettings := TServerSettings.Create;
  try
    ApplyFormTo(TempSettings);

    Screen.Cursor := crHourGlass;
    try
      if TempSettings.TestConnection then
      begin
        ShowMessage('Соединение с базой установлено успешно!');
        FTestPassed := True;
      end
      else
      begin
        ShowMessage('Ошибка подключения. Проверьте параметры и доступность сервера.');
        FTestPassed := False;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    TempSettings.Free;
  end;
end;

procedure TfrmServerSettings.btnGenerateApiKeyClick(Sender: TObject);
begin
  // Генерируем новый надежный ключ и сразу показываем его в поле
  edApiKey.Text := TServerSettings.GenerateSecureApiKey;
  Log.Info('Сгенерирован новый API-ключ в интерфейсе настроек.');
end;

procedure TfrmServerSettings.btnOKClick(Sender: TObject);
begin
  if not ValidateInput then Exit;

  // Если тест ещё не проходили — предлагаем проверить
  if not FTestPassed then
  begin
    if MessageDlg('Вы не проверяли соединение. Проверить сейчас?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      btnTestClick(Sender);

    // Если тест не пройден — не даём закрыть
    if not FTestPassed then Exit;
  end;

  // ИСПРАВЛЕНО: ApplyFormTo вызывается ОДИН раз — только здесь
  ApplyFormTo(FSettings);
  FSettings.SaveToFile;
  ModalResult := mrOk;
end;

function TfrmServerSettings.ValidateInput: Boolean;
begin
  Result := False;
  if Trim(edServer.Text) = '' then
  begin
    ShowMessage('Host обязателен');
    Exit;
  end;
  if (StrToIntDef(edPort.Text, 0) < 1) or (StrToIntDef(edPort.Text, 0) > 65535) then
  begin
    ShowMessage('Порт должен быть от 1 до 65535');
    Exit;
  end;
  if Trim(edDatabase.Text) = '' then
  begin
    ShowMessage('Database обязателен');
    Exit;
  end;
  if Trim(edLogin.Text) = '' then
  begin
    ShowMessage('User обязателен');
    Exit;
  end;
  Result := True;
end;

end.
