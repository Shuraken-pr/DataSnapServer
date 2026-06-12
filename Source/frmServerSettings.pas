unit frmServerSettings;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, cxGraphics, cxControls, cxLookAndFeels,
  cxLookAndFeelPainters, cxContainer, cxEdit, dxLayoutcxEditAdapters,
  dxLayoutControlAdapters, dxLayoutContainer, cxClasses, Vcl.StdCtrls,
  Vcl.Samples.Spin, Vcl.Buttons, cxTextEdit, cxMaskEdit, cxSpinEdit,
  dxLayoutControl, ServerSettings, System.UITypes;

type
  TformServerSettings = class(TForm)
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
    procedure btnOkClick(Sender: TObject);
    procedure btnTestClick(Sender: TObject);
  private
    FSettings: TServerSettings;
    FTestPassed: Boolean;
    function ValidateInput: Boolean;
    procedure ApplyFormToSettings;
  public
    class function Execute(ASettings: TServerSettings): Boolean;
  end;

var
  formServerSettings: TformServerSettings;

implementation

{$R *.dfm}

class function TformServerSettings.Execute(ASettings: TServerSettings): Boolean;
var
  frm: TformServerSettings;
begin
  frm := TformServerSettings.Create(nil);
  try
    frm.FSettings := ASettings;
    // Заполняем поля
    frm.edServer.Text := ASettings.Host;
    frm.edPort.Text := IntToStr(ASettings.Port);
    frm.edDatabase.Text := ASettings.Database;
    frm.edLogin.Text := ASettings.Username;
    frm.edPassword.Text := ASettings.Password;
    frm.FTestPassed := False; // Сбрасываем статус теста при открытии

    Result := (frm.ShowModal = mrOk);
    // Если вернули mrOk, значит FSettings уже обновлены и сохранены внутри btnOKClick
  finally
    frm.Free;
  end;
end;

procedure TformServerSettings.ApplyFormToSettings;
begin
  FSettings.Host := Trim(edServer.Text);
  FSettings.Port := StrToIntDef(edPort.Text, 5432);
  FSettings.Database := Trim(edDatabase.Text);
  FSettings.Username := Trim(edLogin.Text);
  FSettings.Password := edPassword.Text;
end;

procedure TformServerSettings.btnTestClick(Sender: TObject);
var
  TempSettings: TServerSettings;
begin
  if not ValidateInput then Exit;

  // Создаем временный объект с данными из формы
  TempSettings := TServerSettings.Create;
  try
    ApplyFormToSettings; // Обновляем временный объект данными формы
    TempSettings.Host := FSettings.Host;
    TempSettings.Port := FSettings.Port;
    TempSettings.Database := FSettings.Database;
    TempSettings.Username := FSettings.Username;
    TempSettings.Password := FSettings.Password;

    Screen.Cursor := crHourGlass;
    try
      if TempSettings.TestConnection then
      begin
        ShowMessage('✅ Соединение с базой установлено успешно!');
        FTestPassed := True; // Запоминаем, что тест пройден
      end
      else
      begin
        ShowMessage('❌ Ошибка подключения. Проверьте параметры и доступность сервера.');
        FTestPassed := False;
      end;
    finally
      Screen.Cursor := crDefault;
    end;
  finally
    TempSettings.Free;
  end;
end;

procedure TformServerSettings.btnOKClick(Sender: TObject);
begin
  if not ValidateInput then Exit;

  // ТРЕБОВАНИЕ: Сохраняем только если тест пройден
  // (Или можно разрешить сохранение без теста, если убрать эту проверку,
  // но для надежности лучше требовать тест при первой настройке)

  // Если тест еще не проходили — пробуем провести
  if not FTestPassed then
  begin
    if MessageDlg('Вы не проверяли соединение. Проверить сейчас?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
      btnTestClick(Sender); // Запускаем тест

    // Если тест не пройден — не даем закрыть
    if not FTestPassed then Exit;
  end;

  ApplyFormToSettings;
  FSettings.SaveToFile; // Сохраняем в XML
  ModalResult := mrOk;
end;

function TformServerSettings.ValidateInput: Boolean;
begin
  Result := False;
  if Trim(edServer.Text) = '' then begin ShowMessage('Host обязателен'); Exit; end;
  if StrToIntDef(edPort.Text, 0) = 0 then begin ShowMessage('Порт неверен'); Exit; end;
  if Trim(edDatabase.Text) = '' then begin ShowMessage('Database обязателен'); Exit; end;
  if Trim(edLogin.Text) = '' then begin ShowMessage('User обязателен'); Exit; end;
  Result := True;
end;
end.
