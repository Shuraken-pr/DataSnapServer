unit WinDPAPIUtils;

interface

uses
  System.SysUtils, System.Classes, System.NetEncoding, Winapi.Windows;

type
  DATA_BLOB = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PDATA_BLOB = ^DATA_BLOB;

function CryptProtectData(const pDataIn: DATA_BLOB; szDataDescr: PWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD; var pDataOut: DATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

function CryptUnprotectData(const pDataIn: DATA_BLOB; var ppszDataDescr: PWideChar;
  pOptionalEntropy: PDATA_BLOB; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD; var pDataOut: DATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

/// <summary>Шифрует строку с использованием DPAPI (привязка к пользователю/машине)</summary>
function EncryptStringDPAPI(const PlainText: string): string;

/// <summary>Расшифровывает строку, зашифрованную DPAPI</summary>
function DecryptStringDPAPI(const CipherText: string): string;

implementation

uses ServerLogger;

const
  CRYPTPROTECT_UI_FORBIDDEN  = $01;
  CRYPTPROTECT_LOCAL_MACHINE = $04;
  DPAPI_FLAGS = CRYPTPROTECT_UI_FORBIDDEN or CRYPTPROTECT_LOCAL_MACHINE;

function EncryptStringDPAPI(const PlainText: string): string;
var
  BlobIn, BlobOut: DATA_BLOB;
  Bytes: TBytes;
begin
  Result := '';
  if PlainText = '' then Exit;

  Bytes := TEncoding.UTF8.GetBytes(PlainText);
  BlobIn.cbData := Length(Bytes);
  BlobIn.pbData := PByte(Bytes);

  // CRYPTPROTECT_LOCAL_MACHINE (0x04) - привязка к машине.
  // Если убрать этот флаг, будет привязка к текущему пользователю Windows.
  if CryptProtectData(BlobIn, nil, nil, nil, nil, DPAPI_FLAGS, BlobOut) then
  begin
    try
      SetLength(Bytes, BlobOut.cbData);
      Move(BlobOut.pbData^, Bytes[0], BlobOut.cbData);
      Result := TNetEncoding.Base64.EncodeBytesToString(Bytes);
    finally
      LocalFree(HLOCAL(BlobOut.pbData));
    end;
  end
    else
  begin
    Log.Error(Format('WinDPAPIUtils.EncryptString: CryptProtectData failed, code=%d', [GetLastError]));
  end;
end;

function DecryptStringDPAPI(const CipherText: string): string;
var
  BlobIn, BlobOut: DATA_BLOB;
  Bytes, OutBytes: TBytes;
  Descr: PWideChar;
begin
  Result := '';
  if CipherText = '' then Exit;

  Bytes := TNetEncoding.Base64.DecodeStringToBytes(CipherText);
  BlobIn.cbData := Length(Bytes);
  BlobIn.pbData := PByte(Bytes);

  if CryptUnprotectData(BlobIn, Descr, nil, nil, nil, DPAPI_FLAGS, BlobOut) then
  begin
    try
      SetLength(OutBytes, BlobOut.cbData);
      Move(BlobOut.pbData^, OutBytes[0], BlobOut.cbData);
      Result := TEncoding.UTF8.GetString(OutBytes);
    finally
      LocalFree(HLOCAL(BlobOut.pbData));
      if Descr <> nil then LocalFree(HLOCAL(Descr));
    end;
  end
    else
  begin
    Log.Error(Format('WinDPAPIUtils.DecryptString: CryptProtectData failed, code=%d', [GetLastError]));
  end;
end;

end.
