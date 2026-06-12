unit ServerSettings;

interface

uses
  System.SysUtils, System.Classes, System.NetEncoding, Xml.XMLDoc, Xml.XMLIntf,
  System.IOUtils;

type
  TServerSettings = class
  private
    FHost: string;
    FPort: Integer;
    FDatabase: string;
    FUsername: string;
    FPassword: string;
    function GetFilePath: string;
    function EncryptPwd(const Plain: string): string;
    function DecryptPwd(const Encoded: string): string;
  public
    constructor Create;
    function LoadFromFile: Boolean;
    procedure SaveToFile;

    // НОВЫЙ МЕТОД: Проверка соединения
    function TestConnection: Boolean;

    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property Database: string read FDatabase write FDatabase;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
  end;

implementation

// Важно: добавляем FireDAC для создания тестового соединения
uses FireDAC.Comp.Client, FireDAC.Phys.PG, Variants, Dialogs;

{ TServerSettings }

constructor TServerSettings.Create;
begin
  inherited;
  FHost := 'localhost';
  FPort := 5432;
  FDatabase := 'postgres';
  FUsername := 'postgres';
  FPassword := '';
end;

function TServerSettings.GetFilePath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');
end;

// ... (методы EncryptPwd и DecryptPwd без изменений) ...
function TServerSettings.EncryptPwd(const Plain: string): string;
var B: TBytes; I: Integer;
begin
  if Plain = '' then Exit('');
  B := TEncoding.UTF8.GetBytes(Plain);
  for I := 0 to High(B) do B[I] := B[I] xor $A5;
  Result := TNetEncoding.Base64.EncodeBytesToString(B);
end;

function TServerSettings.DecryptPwd(const Encoded: string): string;
var B: TBytes; I: Integer;
begin
  if Encoded = '' then Exit('');
  try
    B := TNetEncoding.Base64.DecodeStringToBytes(Encoded);
    for I := 0 to High(B) do B[I] := B[I] xor $A5;
    Result := TEncoding.UTF8.GetString(B);
  except
    Result := '';
  end;
end;

function TServerSettings.LoadFromFile: Boolean;
var
  Doc: IXMLDocument;
  Root: IXMLNode;
  XmlPath: string;
begin
  Result := False;
  XmlPath := GetFilePath;
  if not TFile.Exists(XmlPath) then Exit;

  try
    Doc := TXMLDocument.Create(nil);
    Doc.LoadFromFile(XmlPath);
    Root := Doc.DocumentElement;

    FHost := Root.ChildValues['host'];
    FPort := StrToIntDef(VarToStr(Root.ChildValues['port']), 5432);
    FDatabase := Root.ChildValues['database'];
    FUsername := Root.ChildValues['username'];
    FPassword := DecryptPwd(Root.ChildValues['password']);

    Result := (FHost <> '') and (FDatabase <> '') and (FUsername <> '');
  except
    Result := False;
  end;
end;

procedure TServerSettings.SaveToFile;
var
  Doc: IXMLDocument;
  Root: IXMLNode;
begin
  Doc := TXMLDocument.Create(nil);
  Doc.Active := True;
  Root := Doc.AddChild('settings');

  Root.AddChild('host').Text := FHost;
  Root.AddChild('port').Text := IntToStr(FPort);
  Root.AddChild('database').Text := FDatabase;
  Root.AddChild('username').Text := FUsername;
  Root.AddChild('password').Text := EncryptPwd(FPassword);

  Doc.SaveToFile(GetFilePath);
end;

// РЕАЛИЗАЦИЯ ПРОВЕРКИ
function TServerSettings.TestConnection: Boolean;
var
  Conn: TFDConnection;
  PGDriver: TFDPhysPGDriverLink;
begin
  Result := False;
  // Создаем драйвер динамически, чтобы метод работал автономно
  PGDriver := TFDPhysPGDriverLink.Create(nil);
  Conn := TFDConnection.Create(nil);
  try
    Conn.Params.DriverID := 'PG';
    Conn.Params.Values['Server'] := FHost;
    Conn.Params.Values['Port'] := IntToStr(FPort);
    Conn.Params.Database := FDatabase;
    Conn.Params.UserName := FUsername;
    Conn.Params.Password := FPassword;
    Conn.LoginPrompt := False;

    try
      Conn.Open;
      Result := True;
    except
      on E: Exception do
        showMessage(E.Message);
      // Соединение не установлено
    end;
  finally
    Conn.Free;
    PGDriver.Free;
  end;
end;

end.
