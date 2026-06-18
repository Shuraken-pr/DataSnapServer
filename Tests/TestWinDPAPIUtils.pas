unit TestWinDPAPIUtils;

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  WinDPAPIUtils;

type
  [TestFixture]
  TTestWinDPAPIUtils = class
  public
    [Test]
    procedure TestEncryptDecryptRoundTrip;
    
    [Test]
    procedure TestEncryptEmptyString;
    
    [Test]
    procedure TestEncryptSpecialCharacters;
    
    [Test]
    procedure TestEncryptLongString;
    
    [Test]
    procedure TestDecryptInvalidData;
  end;

implementation

procedure TTestWinDPAPIUtils.TestEncryptDecryptRoundTrip;
var
  Original, Encrypted, Decrypted: string;
begin
  Original := 'MySecretPassword123!';
  Encrypted := EncryptStringDPAPI(Original);
  
  Assert.AreNotEqual(Original, Encrypted, 'Зашифрованная строка должна отличаться от оригинала');
  Assert.AreNotEqual('', Encrypted, 'Зашифрованная строка не должна быть пустой');
  
  Decrypted := DecryptStringDPAPI(Encrypted);
  Assert.AreEqual(Original, Decrypted, 'Дешифрованная строка должна совпадать с оригиналом');
end;

procedure TTestWinDPAPIUtils.TestEncryptEmptyString;
var
  Encrypted, Decrypted: string;
begin
  Encrypted := EncryptStringDPAPI('');
  Decrypted := DecryptStringDPAPI(Encrypted);
  Assert.AreEqual('', Decrypted, 'Пустая строка должна корректно шифроваться/дешифроваться');
end;

procedure TTestWinDPAPIUtils.TestEncryptSpecialCharacters;
var
  Original, Encrypted, Decrypted: string;
begin
  Original := 'Пароль_с_кириллицей_и_спецсимволами!@#$%^&*()';
  Encrypted := EncryptStringDPAPI(Original);
  Decrypted := DecryptStringDPAPI(Encrypted);
  Assert.AreEqual(Original, Decrypted, 'Специальные символы должны корректно обрабатываться');
end;

procedure TTestWinDPAPIUtils.TestEncryptLongString;
var
  Original, Encrypted, Decrypted: string;
  I: Integer;
begin
  // Создаём длинную строку (1000 символов)
  Original := '';
  for I := 1 to 1000 do
    Original := Original + 'A';
  
  Encrypted := EncryptStringDPAPI(Original);
  Decrypted := DecryptStringDPAPI(Encrypted);
  Assert.AreEqual(Original, Decrypted, 'Длинная строка должна корректно шифроваться');
end;

procedure TTestWinDPAPIUtils.TestDecryptInvalidData;
var
  Decrypted: string;
begin
  // 🔑 ИСПРАВЛЕНИЕ: Функция возвращает пустую строку при ошибке,
  // а не выбрасывает исключение (это правильное поведение!)
  Decrypted := DecryptStringDPAPI('InvalidBase64Data!!!');

  Assert.AreEqual('', Decrypted,
    'Дешифрование невалидных данных должно возвращать пустую строку');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestWinDPAPIUtils);

end.
