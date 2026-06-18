unit TestServerSettings;

interface

uses
  DUnitX.TestFramework,
  ServerSettings,
  System.SysUtils,
  WinDPAPIUtils,
  System.IOUtils;

type
  [TestFixture]
  TTestServerSettings = class
  private
    FSettings: TServerSettings;
    FOriginalFilePath: string;
  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestDefaultValues;

    [Test]
    procedure TestApiKeyGeneration;

    [Test]
    procedure TestApiKeyGenerationUniqueness;

    [Test]
    procedure TestSetAndGetProperties;

    [Test]
    procedure TestPasswordEncryptionRoundTrip;

    [Test]
    procedure TestSaveAndLoadRoundTrip;

    [Test]
    procedure TestLoadFromFileReturnsFalseWhenNoFile;
  end;

implementation

procedure TTestServerSettings.Setup;
begin
  FSettings := TServerSettings.Create;
  // Сохраняем путь к реальному файлу настроек, чтобы восстановить его после теста
  FOriginalFilePath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');
end;

procedure TTestServerSettings.TearDown;
begin
  FSettings.Free;
end;

procedure TTestServerSettings.TestDefaultValues;
var
  FreshSettings: TServerSettings;
begin
  FreshSettings := TServerSettings.Create;
  try
    Assert.AreEqual('localhost', FreshSettings.Host,
      'Host по умолчанию должен быть localhost');
    Assert.AreEqual(5432, FreshSettings.Port,
      'Port по умолчанию должен быть 5432');
    Assert.AreEqual('postgres', FreshSettings.Database,
      'Database по умолчанию должен быть postgres');
    Assert.AreEqual('postgres', FreshSettings.Username,
      'Username по умолчанию должен быть postgres');
    Assert.AreEqual('', FreshSettings.Password,
      'Password по умолчанию должен быть пустым');
    Assert.AreEqual('', FreshSettings.ApiKey,
      'ApiKey по умолчанию должен быть пустым');
  finally
    FreshSettings.Free;
  end;
end;

procedure TTestServerSettings.TestApiKeyGeneration;
var
  Key: string;
begin
  Key := TServerSettings.GenerateSecureApiKey;

  Assert.AreNotEqual('', Key, 'Ключ не должен быть пустым');
  Assert.IsTrue(Length(Key) = 32,
    'Ключ должен быть ровно 32 символа, а не ' + IntToStr(Length(Key)));
end;

procedure TTestServerSettings.TestApiKeyGenerationUniqueness;
var
  Key1, Key2: string;
begin
  Key1 := TServerSettings.GenerateSecureApiKey;
  Key2 := TServerSettings.GenerateSecureApiKey;

  Assert.AreNotEqual(Key1, Key2,
    'Два сгенерированных ключа должны отличаться');
end;

procedure TTestServerSettings.TestSetAndGetProperties;
begin
  FSettings.Host := 'test-host.example.com';
  FSettings.Port := 15432;
  FSettings.Database := 'testdb';
  FSettings.Username := 'testuser';
  FSettings.Password := 'testpass';
  FSettings.ApiKey := 'test-api-key';

  Assert.AreEqual('test-host.example.com', FSettings.Host);
  Assert.AreEqual(15432, FSettings.Port);
  Assert.AreEqual('testdb', FSettings.Database);
  Assert.AreEqual('testuser', FSettings.Username);
  Assert.AreEqual('testpass', FSettings.Password);
  Assert.AreEqual('test-api-key', FSettings.ApiKey);
end;

procedure TTestServerSettings.TestPasswordEncryptionRoundTrip;
var
  OriginalPassword: string;
  EncryptedPassword: string;
  DecryptedPassword: string;
begin
  OriginalPassword := 'SuperSecretPassword123!';

  // Шифруем
  EncryptedPassword := WinDPAPIUtils.EncryptStringDPAPI(OriginalPassword);
  Assert.AreNotEqual(OriginalPassword, EncryptedPassword,
    'Зашифрованный пароль должен отличаться от оригинала');
  Assert.AreNotEqual('', EncryptedPassword,
    'Зашифрованный пароль не должен быть пустым');

  // Дешифруем
  DecryptedPassword := WinDPAPIUtils.DecryptStringDPAPI(EncryptedPassword);
  Assert.AreEqual(OriginalPassword, DecryptedPassword,
    'Дешифрованный пароль должен совпадать с оригиналом');
end;

procedure TTestServerSettings.TestSaveAndLoadRoundTrip;
var
  LoadedSettings: TServerSettings;
  SettingsFile: string;
begin
  SettingsFile := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');

  // Сохраняем текущие настройки
  FSettings.Host := 'roundtrip-host';
  FSettings.Port := 25432;
  FSettings.Database := 'roundtrip-db';
  FSettings.Username := 'roundtrip-user';
  FSettings.Password := 'roundtrip-pass';
  FSettings.ApiKey := 'roundtrip-key';

  FSettings.SaveToFile;

  try
    // Загружаем в новый объект
    LoadedSettings := TServerSettings.Create;
    try
      Assert.IsTrue(LoadedSettings.LoadFromFile,
        'LoadFromFile должен вернуть True для существующего файла');

      Assert.AreEqual('roundtrip-host', LoadedSettings.Host);
      Assert.AreEqual(25432, LoadedSettings.Port);
      Assert.AreEqual('roundtrip-db', LoadedSettings.Database);
      Assert.AreEqual('roundtrip-user', LoadedSettings.Username);
      Assert.AreEqual('roundtrip-pass', LoadedSettings.Password);
      Assert.AreEqual('roundtrip-key', LoadedSettings.ApiKey);
    finally
      LoadedSettings.Free;
    end;
  finally
    // Удаляем тестовый файл, чтобы не мешать реальным настройкам
    if TFile.Exists(SettingsFile) then
      TFile.Delete(SettingsFile);
  end;
end;

procedure TTestServerSettings.TestLoadFromFileReturnsFalseWhenNoFile;
var
  SettingsFile: string;
  FileExistedBefore: Boolean;
begin
  SettingsFile := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'db_settings.xml');
  FileExistedBefore := TFile.Exists(SettingsFile);

  // Временно удаляем файл, если он есть
  if FileExistedBefore then
    TFile.Delete(SettingsFile);

  try
    Assert.IsFalse(FSettings.LoadFromFile,
      'LoadFromFile должен вернуть False, если файл не существует');
  finally
    // Восстанавливаем файл, если он был до теста
    if FileExistedBefore then
    begin
      FSettings.Host := 'localhost';
      FSettings.Port := 5432;
      FSettings.Database := 'postgres';
      FSettings.Username := 'postgres';
      FSettings.SaveToFile;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestServerSettings);

end.
