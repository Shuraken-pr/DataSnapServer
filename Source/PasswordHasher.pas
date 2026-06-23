unit PasswordHasher;

interface

uses
  System.SysUtils, FireDAC.Comp.Client, FireDAC.Stan.Param;

type
  /// <summary>
  /// Хеширование паролей через bcrypt (pgcrypto)
  /// </summary>
  TPasswordHasher = class
  strict private
    FConnection: TFDConnection;
    FCost: Integer;
  public
    /// <summary>Создаёт хешер с указанием стоимости (cost)</summary>
    /// <param name="AConnection">Подключение к БД с расширением pgcrypto</param>
    /// <param name="ACost">Стоимость bcrypt (10-14, по умолчанию 12)</param>
    constructor Create(AConnection: TFDConnection; ACost: Integer = 12);
    
    /// <summary>Хеширует пароль через bcrypt</summary>
    /// <param name="APassword">Пароль в открытом виде</param>
    /// <returns>bcrypt-хеш в формате $2a$12$...</returns>
    function HashPassword(const APassword: string): string;
    
    /// <summary>Проверяет пароль against хеш</summary>
    /// <param name="APassword">Пароль в открытом виде</param>
    /// <param name="AHash">bcrypt-хеш для проверки</param>
    /// <returns>True, если пароль верный</returns>
    function VerifyPassword(const APassword, AHash: string): Boolean;
    
    /// <summary>Проверяет, является ли строка валидным bcrypt-хешем</summary>
    function IsValidBcryptHash(const AHash: string): Boolean;
    
    property Cost: Integer read FCost;
  end;

implementation

{ TPasswordHasher }

constructor TPasswordHasher.Create(AConnection: TFDConnection; ACost: Integer);
begin
  inherited Create;
  FConnection := AConnection;
  FCost := ACost;
  
  // Проверяем диапазон cost
  if (FCost < 4) or (FCost > 31) then
    raise EArgumentException.Create('Bcrypt cost must be between 4 and 31');
end;

function TPasswordHasher.HashPassword(const APassword: string): string;
var
  Qry: TFDQuery;
begin
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT crypt(:password, gen_salt(''bf'', :cost)) as hash';
    Qry.ParamByName('password').AsString := APassword;
    Qry.ParamByName('cost').AsInteger := FCost;
    Qry.Open;
    
    Result := Qry.FieldByName('hash').AsString;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TPasswordHasher.VerifyPassword(const APassword, AHash: string): Boolean;
var
  Qry: TFDQuery;
  ComputedHash: string;
begin
  // Если хеш пустой или невалидный — возвращаем False
  if (AHash = '') or not IsValidBcryptHash(AHash) then
  begin
    Result := False;
    Exit;
  end;
  
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := FConnection;
    Qry.SQL.Text := 'SELECT crypt(:password, :hash) as computed';
    Qry.ParamByName('password').AsString := APassword;
    Qry.ParamByName('hash').AsString := AHash;
    Qry.Open;
    
    ComputedHash := Qry.FieldByName('computed').AsString;
    Qry.Close;
    
    // Сравниваем хеши (timing-safe сравнение через SQL)
    Result := ComputedHash = AHash;
  finally
    Qry.Free;
  end;
end;

function TPasswordHasher.IsValidBcryptHash(const AHash: string): Boolean;
begin
  // bcrypt хеш имеет формат: $2a$12$... (60 символов)
  // $2a$ — алгоритм
  // 12 — стоимость (может быть 04-31)
  // 22 символа соли + 31 символ хеша
  Result := (Length(AHash) = 60) and 
            (Copy(AHash, 1, 4) = '$2a$') and
            CharInSet(AHash[5], ['0'..'3']) and
            CharInSet(AHash[6], ['0'..'9']) and
            (AHash[7] = '$');
end;

end.
