unit TestPasswordHasher;

interface

uses
  DUnitX.TestFramework, FireDAC.Comp.Client, PasswordHasher;

type
  /// <summary>
  /// Модульные тесты для TPasswordHasher
  /// </summary>
  [TestFixture]
  TTestPasswordHasher = class
  strict private
    FConnection: TFDConnection;
    FHasher: TPasswordHasher;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    
    /// <summary>Тест 1: HashPassword возвращает валидный bcrypt-формат</summary>
    [Test]
    procedure TestHashPassword_ReturnsValidBcryptFormat;
    
    /// <summary>Тест 2: Разные хеши для одного пароля (солёность)</summary>
    [Test]
    procedure TestHashPassword_DifferentHashesForSamePassword;
    
    /// <summary>Тест 3: VerifyPassword возвращает True для верного пароля</summary>
    [Test]
    procedure TestVerifyPassword_CorrectPassword;
    
    /// <summary>Тест 4: VerifyPassword возвращает False для неверного пароля</summary>
    [Test]
    procedure TestVerifyPassword_WrongPassword;
  end;

implementation

uses
  System.SysUtils, FireDAC.Stan.Def, FireDAC.Phys.PG, FireDAC.Phys.PGDef,
  Data.DB;

{ TTestPasswordHasher }

procedure TTestPasswordHasher.Setup;
begin
  // Создаём тестовое подключение к тестовой БД
  FConnection := TFDConnection.Create(nil);
  FConnection.Params.Clear;
  FConnection.DriverName := 'PG';
  FConnection.Params.Add('Server=localhost');
  FConnection.Params.Add('Port=5433');
  FConnection.Params.Add('Database=audit_test');
  FConnection.Params.Add('User_Name=test_user');
  FConnection.Params.Add('Password=test_password');
  FConnection.Connected := True;
  
  // Создаём хешер с cost=12 (по умолчанию)
  FHasher := TPasswordHasher.Create(FConnection);
end;

procedure TTestPasswordHasher.TearDown;
begin
  FHasher.Free;
  FConnection.Connected := False;
  FConnection.Free;
end;

procedure TTestPasswordHasher.TestHashPassword_ReturnsValidBcryptFormat;
var
  Hash: string;
begin
  // Act: хешируем пароль
  Hash := FHasher.HashPassword('test_password');
  
  // Assert: проверяем формат bcrypt
  Assert.IsTrue(FHasher.IsValidBcryptHash(Hash), 
    'Hash should be in valid bcrypt format');
  
  // Проверяем длину (60 символов)
  Assert.AreEqual(60, Length(Hash), 'Bcrypt hash should be 60 characters');
  
  // Проверяем префикс $2a$
  Assert.AreEqual('$2a$', Copy(Hash, 1, 4), 'Hash should start with $2a$');
end;

procedure TTestPasswordHasher.TestHashPassword_DifferentHashesForSamePassword;
var
  Hash1, Hash2: string;
begin
  // Act: хешируем один и тот же пароль дважды
  Hash1 := FHasher.HashPassword('test_password');
  Hash2 := FHasher.HashPassword('test_password');
  
  // Assert: хеши должны быть разными (из-за случайной соли)
  Assert.AreNotEqual(Hash1, Hash2, 
    'Same password should produce different hashes due to salt');
  
  // Но оба должны быть валидными
  Assert.IsTrue(FHasher.IsValidBcryptHash(Hash1), 'Hash1 should be valid');
  Assert.IsTrue(FHasher.IsValidBcryptHash(Hash2), 'Hash2 should be valid');
end;

procedure TTestPasswordHasher.TestVerifyPassword_CorrectPassword;
var
  Hash: string;
  IsValid: Boolean;
begin
  // Arrange: хешируем пароль
  Hash := FHasher.HashPassword('correct_password');
  
  // Act: проверяем верный пароль
  IsValid := FHasher.VerifyPassword('correct_password', Hash);
  
  // Assert: должно быть True
  Assert.IsTrue(IsValid, 'Correct password should verify successfully');
end;

procedure TTestPasswordHasher.TestVerifyPassword_WrongPassword;
var
  Hash: string;
  IsValid: Boolean;
begin
  // Arrange: хешируем пароль
  Hash := FHasher.HashPassword('correct_password');
  
  // Act: проверяем неверный пароль
  IsValid := FHasher.VerifyPassword('wrong_password', Hash);
  
  // Assert: должно быть False
  Assert.IsFalse(IsValid, 'Wrong password should not verify');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestPasswordHasher);

end.
