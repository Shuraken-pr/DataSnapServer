unit TestUploadUtils;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.Classes, System.IOUtils;

type
  [TestFixture]
  TTestUploadUtils = class
  private
    FTempDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure TestIsValidJpegMagic_Valid;

    [Test]
    procedure TestIsValidJpegMagic_Invalid;

    [Test]
    procedure TestIsValidJpegMagic_Empty;

    [Test]
    procedure TestComputeSHA256_Deterministic;

    [Test]
    procedure TestComputeSHA256_Length;

    [Test]
    procedure TestGenerateFileUUID_Unique;

    [Test]
    procedure TestGenerateFileUUID_Format;

    [Test]
    procedure TestEnsureAuditDir_CreatesHierarchy;

    [Test]
    procedure TestEnsureAuditDir_YearMonthDay;

    [Test]
    procedure TestSaveUploadedFile_Atomic;

    [Test]
    procedure TestSaveUploadedFile_Content;
  end;

implementation

uses UploadUtils;

{ TTestUploadUtils }

procedure TTestUploadUtils.Setup;
begin
  FTempDir := TPath.Combine(TPath.GetTempPath, 'TestUploadUtils_' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(FTempDir);
end;

procedure TTestUploadUtils.TearDown;
begin
  if TDirectory.Exists(FTempDir) then
    TDirectory.Delete(FTempDir, True);
end;

procedure TTestUploadUtils.TestIsValidJpegMagic_Valid;
var
  Stream: TBytesStream;
  JPEGHeader: array[0..2] of Byte;
begin
  Stream := TBytesStream.Create(nil);
  try
    JPEGHeader[0] := $FF;
    JPEGHeader[1] := $D8;
    JPEGHeader[2] := $FF;
    Stream.Write(JPEGHeader, 3);
    Stream.Position := 0;
    Assert.IsTrue(IsValidJpegMagic(Stream));
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestIsValidJpegMagic_Invalid;
var
  Stream: TBytesStream;
  PNGHeader: array[0..2] of Byte;
begin
  Stream := TBytesStream.Create(nil);
  try
    PNGHeader[0] := $89;
    PNGHeader[1] := $50;
    PNGHeader[2] := $4E;
    Stream.Write(PNGHeader, 3);
    Stream.Position := 0;
    Assert.IsFalse(IsValidJpegMagic(Stream));
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestIsValidJpegMagic_Empty;
var
  Stream: TBytesStream;
begin
  Stream := TBytesStream.Create(nil);
  try
    Stream.Position := 0;
    Assert.IsFalse(IsValidJpegMagic(Stream));
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestComputeSHA256_Deterministic;
var
  Stream: TBytesStream;
  Hash1, Hash2: string;
begin
  Stream := TBytesStream.Create(TEncoding.UTF8.GetBytes('test data'));
  try
    Hash1 := ComputeSHA256(Stream);
    Stream.Position := 0;
    Hash2 := ComputeSHA256(Stream);
    Assert.AreEqual(Hash1, Hash2);
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestComputeSHA256_Length;
var
  Stream: TBytesStream;
  Hash: string;
begin
  Stream := TBytesStream.Create(TEncoding.UTF8.GetBytes('any content'));
  try
    Hash := ComputeSHA256(Stream);
    Assert.AreEqual(64, Length(Hash)); // Hex-encoded SHA256
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestGenerateFileUUID_Unique;
var
  UUID1, UUID2: string;
  I: Integer;
begin
  for I := 1 to 100 do
  begin
    UUID1 := GenerateFileUUID;
    UUID2 := GenerateFileUUID;
    Assert.AreNotEqual(UUID1, UUID2);
  end;
end;

procedure TTestUploadUtils.TestGenerateFileUUID_Format;
var
  UUID: string;
begin
  UUID := GenerateFileUUID;
  Assert.AreEqual(36, UUID.Length); // xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Assert.IsFalse(UUID.Contains('{'));
  Assert.IsFalse(UUID.Contains('}'));
end;

procedure TTestUploadUtils.TestEnsureAuditDir_CreatesHierarchy;
var
  Dir: string;
  Exists: Boolean;
begin
  Dir := EnsureAuditDir(FTempDir, EncodeDate(2026, 6, 18));
  Exists := TDirectory.Exists(Dir);
  Assert.IsTrue(Exists);
end;

procedure TTestUploadUtils.TestEnsureAuditDir_YearMonthDay;
var
  Dir: string;
begin
  Dir := EnsureAuditDir(FTempDir, EncodeDate(2026, 6, 18));
  Assert.IsTrue(Dir.Contains('2026'));
  Assert.IsTrue(Dir.Contains('6'));
  Assert.IsTrue(Dir.Contains('18'));
end;

procedure TTestUploadUtils.TestSaveUploadedFile_Atomic;
var
  Stream: TBytesStream;
  FileUUID, FinalPath: string;
  Exists: Boolean;
  HasTmp: Boolean;
begin
  FileUUID := GenerateFileUUID;
  Stream := TBytesStream.Create(TEncoding.UTF8.GetBytes('test content'));
  try
    Assert.IsTrue(SaveUploadedFile(Stream, FTempDir, FileUUID, FinalPath));
    Exists := TFile.Exists(FinalPath);
    HasTmp := TFile.Exists(FinalPath + '.tmp');
    Assert.IsTrue(Exists, 'Final file should exist');
    Assert.IsFalse(HasTmp, '.tmp file should not remain');
  finally
    Stream.Free;
  end;
end;

procedure TTestUploadUtils.TestSaveUploadedFile_Content;
var
  Stream: TBytesStream;
  FileUUID, FinalPath, ReadBack: string;
  FS: TFileStream;
  Bytes: TBytes;
begin
  FileUUID := GenerateFileUUID;
  Stream := TBytesStream.Create(TEncoding.UTF8.GetBytes('jpeg payload'));
  try
    SaveUploadedFile(Stream, FTempDir, FileUUID, FinalPath);

    FS := TFileStream.Create(FinalPath, fmOpenRead);
    try
      SetLength(Bytes, FS.Size);
      FS.Read(Bytes[0], FS.Size);
      ReadBack := TEncoding.UTF8.GetString(Bytes);
      Assert.AreEqual('jpeg payload', ReadBack);
    finally
      FS.Free;
    end;
  finally
    Stream.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUploadUtils);

end.
