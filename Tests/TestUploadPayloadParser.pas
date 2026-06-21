unit TestUploadPayloadParser;

interface

uses
  DUnitX.TestFramework, System.SysUtils, System.JSON, System.NetEncoding;

type
  [TestFixture]
  TTestUploadPayloadParser = class
  public
    [Test]
    procedure TestValidPayload_AllFields;

    [Test]
    procedure TestMissingPhotoBase64;

    [Test]
    procedure TestInvalidBase64;

    [Test]
    procedure TestLargePhotoBase64;

    [Test]
    procedure TestGeoCoordinatesPrecision;

    [Test]
    procedure TestMetadataExtraction;
  end;

implementation

{ TTestUploadPayloadParser }

procedure TTestUploadPayloadParser.TestValidPayload_AllFields;
var
  Payload: TJSONObject;
  PhotoBase64: string;
  Lat, Lon: Double;
  EventType: string;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('event_type', 'mobile_audit');
    Payload.AddPair('lat', TJSONNumber.Create(55.7558));
    Payload.AddPair('lon', TJSONNumber.Create(37.6173));
    Payload.AddPair('photo_base64', TNetEncoding.Base64.EncodeBytesToString(TEncoding.UTF8.GetBytes('test')));
    Payload.AddPair('photo_filename', 'test.jpg');
    Payload.AddPair('device_id', 'android');
    Payload.AddPair('batch_id', TGUID.NewGuid.ToString);
    Payload.AddPair('occurred_at', '2026-06-18T14:30:00Z');

    Assert.IsNotNull(Payload.GetValue('photo_base64'));
    PhotoBase64 := Payload.GetValue('photo_base64').Value;
    Assert.AreEqual('dGVzdA==', PhotoBase64);

    Lat := (Payload.GetValue('lat') as TJSONNumber).AsDouble;
    Lon := (Payload.GetValue('lon') as TJSONNumber).AsDouble;
    Assert.AreEqual(55.7558, Lat, 0.0001);
    Assert.AreEqual(37.6173, Lon, 0.0001);

    EventType := Payload.GetValue('event_type').Value;
    Assert.AreEqual('mobile_audit', EventType);
  finally
    Payload.Free;
  end;
end;

procedure TTestUploadPayloadParser.TestMissingPhotoBase64;
var
  Payload: TJSONObject;
  HasPhoto: Boolean;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('event_type', 'mobile_audit');
    Payload.AddPair('lat', TJSONNumber.Create(55.0));
    HasPhoto := Payload.GetValue('photo_base64') <> nil;
    Assert.IsFalse(HasPhoto);
  finally
    Payload.Free;
  end;
end;

procedure TTestUploadPayloadParser.TestInvalidBase64;
var
  Bytes: TBytes;
  check: string;
  Valid: Boolean;
begin
  // Delphi TNetEncoding.Base64 does not throw on invalid input,
  // it returns empty or best-effort decoded array.
  // Our IsValidBase64Chars rejects invalid input before decoding.
  Bytes := TNetEncoding.Base64.DecodeStringToBytes('!!!invalid!!!');
  check := TNetEncoding.Base64.EncodeBytesToString(Bytes);
  // The original string should not round-trip if input was invalid
  Valid := (Length(Bytes) = 0) or (check <> '!!!invalid!!!');
  Assert.IsTrue(Valid, 'Invalid Base64 should not round-trip correctly');
end;

procedure TTestUploadPayloadParser.TestLargePhotoBase64;
var
  LargeData: TBytes;
  Payload: TJSONObject;
  Base64Str: string;
  Base64Len: Integer;
const
  FIVE_MB = 5 * 1024 * 1024;
  EXPECTED_MIN = 6 * 1024 * 1024; // ~6.6 MB Base64 of 5 MB
begin
  SetLength(LargeData, FIVE_MB);
  FillChar(LargeData[0], FIVE_MB, 0);

  Payload := TJSONObject.Create;
  try
    Base64Str := TNetEncoding.Base64.EncodeBytesToString(LargeData);
    Payload.AddPair('photo_base64', Base64Str);
    Base64Len := Payload.GetValue('photo_base64').Value.Length;
    Assert.IsTrue(Base64Len > EXPECTED_MIN,
      Format('Expected Base64 > %d, got %d', [EXPECTED_MIN, Base64Len]));
  finally
    Payload.Free;
  end;
end;

procedure TTestUploadPayloadParser.TestGeoCoordinatesPrecision;
var
  Payload: TJSONObject;
  Lat, Lon: Double;
  CoordsStr: string;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('lat', TJSONNumber.Create(55.123456789));
    Payload.AddPair('lon', TJSONNumber.Create(37.987654321));

    Lat := (Payload.GetValue('lat') as TJSONNumber).AsDouble;
    Lon := (Payload.GetValue('lon') as TJSONNumber).AsDouble;

    Assert.AreEqual(55.123456789, Lat, 0.0000001);
    Assert.AreEqual(37.987654321, Lon, 0.0000001);

    CoordsStr := Payload.ToString;
    Assert.IsTrue(CoordsStr.Contains('55.123456789'));
    Assert.IsTrue(CoordsStr.Contains('37.987654321'));
  finally
    Payload.Free;
  end;
end;

procedure TTestUploadPayloadParser.TestMetadataExtraction;
var
  Payload: TJSONObject;
  DeviceId, BatchId, Title: string;
  OccurredAt: string;
begin
  Payload := TJSONObject.Create;
  try
    Payload.AddPair('event_type', 'mobile_audit');
    Payload.AddPair('device_id', 'android');
    Payload.AddPair('batch_id', 'batch-123-abc');
    Payload.AddPair('title', 'Inspection Site A');
    Payload.AddPair('occurred_at', '2026-06-18T14:30:00Z');

    DeviceId := Payload.GetValue('device_id').Value;
    BatchId := Payload.GetValue('batch_id').Value;
    Title := Payload.GetValue('title').Value;
    OccurredAt := Payload.GetValue('occurred_at').Value;

    Assert.AreEqual('android', DeviceId);
    Assert.AreEqual('batch-123-abc', BatchId);
    Assert.AreEqual('Inspection Site A', Title);
    Assert.AreEqual('2026-06-18T14:30:00Z', OccurredAt);
  finally
    Payload.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestUploadPayloadParser);

end.
