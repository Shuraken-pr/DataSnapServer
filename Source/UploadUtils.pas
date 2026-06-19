unit UploadUtils;

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.Hash;

function IsValidJpegMagic(const Stream: TStream): Boolean;
function ComputeSHA256(const Stream: TStream): string;
function EnsureAuditDir(const BasePath: string; const Date: TDateTime): string;
function GenerateFileUUID: string;
function SaveUploadedFile(const Stream: TStream; const DirPath, FileUUID: string; out FinalPath: string): Boolean;

implementation

function IsValidJpegMagic(const Stream: TStream): Boolean;
var
  Magic: array[0..2] of Byte;
  SavedPos: Int64;
begin
  Result := False;
  if Stream.Size < 3 then Exit;
  SavedPos := Stream.Position;
  Stream.Position := 0;
  if Stream.Read(Magic, 3) = 3 then
    Result := (Magic[0] = $FF) and (Magic[1] = $D8) and (Magic[2] = $FF);
  Stream.Position := SavedPos;
end;

function ComputeSHA256(const Stream: TStream): string;
var
  Hash: THashSHA2;
  Bytes: TBytes;
  SavedPos: Int64;
begin
  SavedPos := Stream.Position;
  Stream.Position := 0;
  SetLength(Bytes, Stream.Size);
  Stream.Read(Bytes[0], Stream.Size);
  Hash := THashSHA2.Create;
  Hash.Update(Bytes);
  Result := Hash.HashAsString;
  Stream.Position := SavedPos;
end;

function EnsureAuditDir(const BasePath: string; const Date: TDateTime): string;
var
  Year, Month, Day: Word;
begin
  DecodeDate(Date, Year, Month, Day);
  Result := TPath.Combine(TPath.Combine(TPath.Combine(BasePath, IntToStr(Year)), IntToStr(Month)), IntToStr(Day));
  if not TDirectory.Exists(Result) then
    TDirectory.CreateDirectory(Result);
end;

function GenerateFileUUID: string;
begin
  Result := TGUID.NewGuid.ToString;
  Result := StringReplace(Result, '{', '', [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
end;

function SaveUploadedFile(const Stream: TStream; const DirPath, FileUUID: string; out FinalPath: string): Boolean;
var
  FS: TFileStream;
  TmpPath: string;
  SavedPos: Int64;
begin
  FinalPath := TPath.Combine(DirPath, FileUUID + '.jpg');
  TmpPath := FinalPath + '.tmp';
  SavedPos := Stream.Position;
  try
    FS := TFileStream.Create(TmpPath, fmCreate);
    try
      Stream.Position := 0;
      FS.CopyFrom(Stream, Stream.Size);
    finally
      FS.Free;
    end;
    TFile.Move(TmpPath, FinalPath);
    Result := True;
  except
    if TFile.Exists(TmpPath) then
      TFile.Delete(TmpPath);
    raise;
  end;
  Stream.Position := SavedPos;
end;

end.
