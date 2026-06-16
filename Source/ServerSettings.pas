unit ServerSettings;

interface

uses
  System.SysUtils, System.Classes, Xml.XMLDoc, Xml.XMLIntf,
  System.IOUtils;

type
  TServerSettings = class
  private
    FHost: string;
    FPort: Integer;
    FDatabase: string;
    FUsername: string;
    FPassword: string;
    FApiKey: string;
    function GetFilePath: string;
    function GetApiKey: string;
    procedure SetApiKey(const Value: string);
  public
    constructor Create;
    function LoadFromFile: Boolean;
    procedure SaveToFile;

    // НОВЫЙ МЕТОД: Проверка соединения
    function TestConnection: Boolean;

    property ApiKey: string read GetApiKey write SetApiKey; // <--- НОВОЕ СВОЙСТВО
    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property Database: string read FDatabase write FDatabase;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    /// <summary>Генерирует криптографически стойкий 32-символьный API-ключ</summary>
    class function GenerateSecureApiKey: string;
  end;

var
  AppSettings: TServerSettings;

const
  /// <summary>Имя подключения, используемое в FDManager и TFDConnection</summary>
  CONN_DEF_NAME = 'PgServerConn';

implementation

// Важно: добавляем FireDAC для создания тестового соединения
uses FireDAC.Comp.Client, FireDAC.Phys.PG, Variants,
  WinDPAPIUtils, ServerLogger, Winapi.Windows;

{ TServerSettings }
var
  _PGDriverLink: TFDPhysPGDriverLink = nil;

constructor TServerSettings.Create;
begin
  inherited;
  FHost := 'localhost';
  FPort := 5432;
  FDatabase := 'postgres';
  FUsername := 'postgres';
  FPassword := '';
  FApiKey := '';
end;

function RtlGenRandom(RandomBuffer: Pointer; RandomBufferLength: Cardinal): BOOL;
  stdcall; external 'Advapi32.dll' name 'SystemFunction036';

class function TServerSettings.GenerateSecureApiKey: string;
const
  Chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
var
  I, Idx: Integer;
  Buf: array[0..31] of Byte;
begin
  Result := '';
  if not RtlGenRandom(@Buf[0], SizeOf(Buf)) then
    RaiseLastOSError;
  for I := 0 to 31 do
  begin
    Idx := Buf[I] mod Length(Chars);
    Result := Result + Chars[Idx + 1];
  end;
end;
function TServerSettings.GetApiKey: string;
begin
  Result := FApiKey;
end;

procedure TServerSettings.SetApiKey(const Value: string);
begin
  FApiKey := Value.Trim;
end;

function TServerSettings.GetFilePath: string;
begin
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');
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
    FPassword := DecryptStringDPAPI(Root.ChildValues['password']);
    // Расшифровка API-ключа
    FApiKey := DecryptStringDPAPI(Root.ChildValues['apikey']);

    // Защита от повреждения файла: если ключ не расшифровался или пуст, генерируем новый
    if FApiKey = '' then
      FApiKey := GenerateSecureApiKey;

    Result := (FHost <> '') and (FDatabase <> '') and (FUsername <> '');
  except
    on E: Exception do
    begin
      Log.Error('ServerSettings.LoadFromFile: ' + E.Message);
      Result := False;
    end;
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
  Root.AddChild('password').Text := EncryptStringDPAPI(FPassword);
  Root.AddChild('apikey').Text := EncryptStringDPAPI(FApiKey);

  Doc.SaveToFile(GetFilePath);
end;

// РЕАЛИЗАЦИЯ ПРОВЕРКИ
function TServerSettings.TestConnection: Boolean;
var
  Conn: TFDConnection;
begin
  // Создаем драйвер динамически, чтобы метод работал автономно
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
      Log.Info('Тестовое подключение к БД успешно.');
    except
      on E: Exception do
      begin
        // Логируем ошибку. Метод Log.Exception автоматически добавит стек вызова (StackTrace)
        Log.Error('Ошибка тестового подключения к БД: ' + E.Message);
        Log.LogException(e);
        Result := False;
      end;
    end;
  finally
    Conn.Free;
  end;
end;

initialization
  // Создаём драйвер PostgreSQL один раз при загрузке модуля
  _PGDriverLink := TFDPhysPGDriverLink.Create(nil);
  AppSettings := TServerSettings.Create;
finalization
  if _PGDriverLink <> nil then
    FreeAndNil(_PGDriverLink);
  AppSettings.Free;
end.
