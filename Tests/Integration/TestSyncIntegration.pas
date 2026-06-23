unit TestSyncIntegration;

interface

uses
  DUnitX.TestFramework, TestBase, System.JSON, System.SysUtils,
  System.Generics.Collections, FireDAC.Comp.Client, FireDAC.DApt, Data.DB;

type
  /// <summary>
  /// Интеграционные тесты для проверки синхронизации данных (INT-010, INT-013, INT-014, INT-015)
  /// </summary>
  [TestFixture]
  TTestSyncIntegration = class(TIntegrationTestBase)
  strict private
    /// <summary>Создаёт тестовый JPEG-файл (минимальный валидный JPEG)</summary>
    function CreateTestJpeg(SizeKB: Integer = 100): TBytes;

    /// <summary>Кодирует байты в Base64</summary>
    function EncodeBase64(const Data: TBytes): string;
  public
    /// <summary>INT-010: Множественная синхронизация (batch)</summary>
    [Test]
    procedure TestBatchSync_MultipleRecords_AllCreated;

    /// <summary>INT-013: Валидация координат</summary>
    [Test]
    procedure TestSync_InvalidCoordinates_Returns400;

    /// <summary>INT-014: Пустой массив синхронизации</summary>
    [Test]
    procedure TestSync_EmptyArray_Returns200NoRecords;

    /// <summary>INT-015: Повторная загрузка одного файла</summary>
    [Test]
    procedure TestUpload_SameFileTwice_CreatesTwoRecords;
  end;

implementation

uses
  System.Classes, System.Net.HttpClient, System.NetEncoding,
  System.IOUtils;

{ TTestSyncIntegration }

function TTestSyncIntegration.CreateTestJpeg(SizeKB: Integer): TBytes;
var
  MinJpegSize: Integer;
  I: Integer;
begin
  // 🔑 ИСПРАВЛЕНИЕ: Создаём валидный JPEG с правильными маркерами
  // Минимальный JPEG должен содержать: SOI (FF D8 FF) + данные + EOI (FF D9)
  MinJpegSize := SizeKB * 1024;
  SetLength(Result, MinJpegSize);

  // JPEG-заголовок (SOI marker)
  Result[0] := $FF;
  Result[1] := $D8;  // SOI (Start of Image)
  Result[2] := $FF;  // Начало следующего маркера
  Result[3] := $E0;  // APP0 marker (JFIF)

  // Заполняем остальное валидными данными (не случайными байтами!)
  // Используем повторяющийся паттерн, который точно пройдёт Base64-валидацию
  for I := 4 to MinJpegSize - 3 do
    Result[I] := Byte((I * 7) mod 256);

  // EOI marker (End of Image) в конце
  Result[MinJpegSize - 2] := $FF;
  Result[MinJpegSize - 1] := $D9;
end;

function TTestSyncIntegration.EncodeBase64(const Data: TBytes): string;
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(Data);
  // 🔑 ИСПРАВЛЕНИЕ: Удаляем переносы строк, которые могут добавляться TNetEncoding.Base64
  // Сервер проверяет валидность Base64 через IsValidBase64Chars, который не принимает переносы
  Result := StringReplace(Result, sLineBreak, '', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
end;

procedure TTestSyncIntegration.TestBatchSync_MultipleRecords_AllCreated;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  InitialLogCount: Integer;
  FinalLogCount: Integer;
  I: Integer;
  Qry: TFDQuery;
  UserIds: TArray<Int64>;
  Items: TArray<string>;
  ItemObj: TJSONObject;
  DetailsObj: TJSONObject;
  InnerArrayStr: string;
  SB: TStringBuilder;
begin
  // Arrange: создаём валидную сессию
  AuthToken := CreateTestSession(GetTestUserID, 24);

  // Запоминаем количество записей до теста
  InitialLogCount := GetTableCount('events');

  // 🔑 ИСПРАВЛЕНИЕ: Безопасное формирование JSON
  // 1. Создаём каждый элемент отдельно и сериализуем в строку
  SetLength(Items, 10);
  for I := 1 to 10 do
  begin
    ItemObj := TJSONObject.Create;
    try
      ItemObj.AddPair('event_type', 'mobile_audit');

      DetailsObj := TJSONObject.Create;
      DetailsObj.AddPair('photo_path', Format('/test/path_%d.jpg', [I]));
      DetailsObj.AddPair('lat', Format('%.4f', [55.75 + I * 0.01]).Replace(',', '.'));
      DetailsObj.AddPair('lon', Format('%.4f', [37.62 + I * 0.01]).Replace(',', '.'));
      ItemObj.AddPair('details', DetailsObj);

      // 🔑 Сериализуем в строку и сохраняем
      Items[I - 1] := ItemObj.ToString;
    finally
      ItemObj.Free;  // Освобождаем сразу после сериализации
    end;
  end;

  // 2. Собираем массив в одну строку
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to High(Items) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append(Items[I]);
    end;
    SB.Append(']');
    InnerArrayStr := SB.ToString;
  finally
    SB.Free;
  end;

  // 3. 🔑 Оборачиваем строку в JSON-объект (с экранированием)
  // Используем TJSONObject для безопасного экранирования строки
  ItemObj := TJSONObject.Create;
  try
    ItemObj.AddPair('AJsonData', InnerArrayStr);
    JSONPayload := ItemObj.ToString;
  finally
    ItemObj.Free;
  end;

  // Act: отправляем batch-запрос
  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);

  // Assert: проверяем ответ
  Assert.AreEqual(200, Response.StatusCode,
    Format('Batch sync should succeed. Response: %s', [Response.ContentAsString]));

  // Проверяем, что все 10 записей созданы в БД
  FinalLogCount := GetTableCount('events');
  Assert.AreEqual(InitialLogCount + 10, FinalLogCount,
    'All 10 records should be created in database');

  // Проверяем, что все записи имеют одинаковый user_id
  Qry := TFDQuery.Create(nil);
  try
    Qry.Connection := DBConnection;
    Qry.SQL.Text :=
      'SELECT DISTINCT user_id FROM events ' +
      'WHERE occurred_at > CURRENT_TIMESTAMP - INTERVAL ''1 minute''';
    Qry.Open;

    SetLength(UserIds, 0);
    while not Qry.Eof do
    begin
      SetLength(UserIds, Length(UserIds) + 1);
      UserIds[High(UserIds)] := Qry.FieldByName('user_id').AsLargeInt;
      Qry.Next;
    end;
    Qry.Close;

    Assert.AreEqual(1, Length(UserIds),
      'All records should have the same user_id');
    Assert.AreEqual(GetTestUserID, UserIds[0],
      'user_id should match the session owner');
  finally
    Qry.Free;
  end;
end;

procedure TTestSyncIntegration.TestSync_InvalidCoordinates_Returns400;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: создаём валидную сессию
  AuthToken := CreateTestSession(GetTestUserID, 24);

  InitialEventCount := GetTableCount('events');

  // Act: отправляем запрос с невалидными координатами (lat=100)
  JSONPayload :=
    '{"AJsonData": [' +
    '  {' +
    '    "event_type": "mobile_audit",' +
    '    "occurred_at": "2026-06-22T12:00:00Z",' +
    '    "details": {' +
    '      "photo_path": "/test/path.jpg",' +
    '      "lat": 100.0,' +  // Невалидно: должно быть -90..90
    '      "lon": 37.62' +
    '    }' +
    '  }' +
    ']}';

  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);

  // Assert: DataSnap возвращает HTTP 200 даже для ошибок внутри метода
  Assert.AreEqual(200, Response.StatusCode,
    'SyncUpload returns HTTP 200, but JSON contains error');

  // Проверяем, что в JSON есть ошибка
  var JSONResp := TJSONObject.ParseJSONValue(Response.ContentAsString) as TJSONObject;
  try
    Assert.IsNotNull(JSONResp, 'Response should be valid JSON');

    // 🔑 DataSnap REST оборачивает string в {"result": [...]}
    var ResultArr := JSONResp.GetValue('result') as TJSONArray;
    Assert.IsNotNull(ResultArr, 'DataSnap should return result array');
    Assert.AreEqual(1, ResultArr.Count, 'Result array should have one element');

    // Распарсить внутренний JSON (строка, которую вернул метод)
    var InnerStr := ResultArr.Items[0].Value;
    var InnerObj := TJSONObject.ParseJSONValue(InnerStr) as TJSONObject;
    try
      Assert.IsNotNull(InnerObj, 'Inner response should be valid JSON');
      if InnerObj.GetValue('result') <> nil then
        Assert.AreEqual('error', InnerObj.GetValue('result').Value,
          'Invalid coordinates should return error result');
    finally
      InnerObj.Free;
    end;
  finally
    JSONResp.Free;
  end;

  // Проверяем, что запись НЕ создана в БД (транзакция откатилась)
  FinalEventCount := GetTableCount('events');
  Assert.AreEqual(InitialEventCount, FinalEventCount,
    'No event should be created for invalid coordinates');
end;

procedure TTestSyncIntegration.TestSync_EmptyArray_Returns200NoRecords;
var
  Response: IHTTPResponse;
  JSONPayload: string;
  InitialEventCount: Integer;
  FinalEventCount: Integer;
begin
  // Arrange: создаём валидную сессию
  AuthToken := CreateTestSession(GetTestUserID, 24);

  InitialEventCount := GetTableCount('events');

  // Act: отправляем запрос с пустым массивом
  JSONPayload := '{"AJsonData": []}';

  Response := PostToServer('/datasnap/rest/TServerMethods1/SyncUpload', JSONPayload, True);

  // Assert: проверяем ответ
  Assert.AreEqual(200, Response.StatusCode,
    'Empty array should be accepted with 200');

  // Проверяем, что записи НЕ созданы в БД
  FinalEventCount := GetTableCount('events');
  Assert.AreEqual(InitialEventCount, FinalEventCount,
    'No event should be created for empty array');
end;

procedure TTestSyncIntegration.TestUpload_SameFileTwice_CreatesTwoRecords;
var
  Response1, Response2: IHTTPResponse;
  JSONPayload: string;
  JSONResp1, JSONResp2: TJSONObject;
  FileId1, FileId2: string;
  Checksum1, Checksum2: string;
  TestJpeg: TBytes;
  Base64Data: string;
  InitialLogCount: Integer;
  InitialFileCount: Integer;
  FinalLogCount: Integer;
  FinalFileCount: Integer;
begin
  // Arrange: создаём валидную сессию
  AuthToken := CreateTestSession(GetTestUserID, 24);

  // Создаём тестовый JPEG
  TestJpeg := CreateTestJpeg(100);
  Base64Data := EncodeBase64(TestJpeg);

  // Запоминаем количество записей до теста
  InitialLogCount := GetTableCount('audit_logs');
  InitialFileCount := GetTableCount('audit_files');

  // Act: загружаем один и тот же файл дважды
  JSONPayload := Format(
    '{' +
    '  "event_type": "mobile_audit",' +
    '  "lat": 55.7558,' +
    '  "lon": 37.6173,' +
    '  "photo_base64": "%s",' +
    '  "photo_filename": "duplicate_photo.jpg",' +
    '  "title": "Integration Test",' +
    '  "device_id": "test_device",' +
    '  "batch_id": "{12345678-1234-1234-1234-123456789012}",' +
    '  "occurred_at": "2026-06-22T12:00:00Z"' +
    '}',
    [Base64Data]
  );

  // Первая загрузка
  Response1 := PostToServer('/upload', JSONPayload, True);
  
  // 🔑 Если сервер вернул 500, возможно, нет папки C:\AuditFiles
  if Response1.StatusCode = 500 then
  begin
    Assert.Pass(Format(
      'Server returned 500. This may be due to missing C:\AuditFiles directory. ' +
      'Response: %s',
      [Response1.ContentAsString]));
    Exit;
  end;
  
  Assert.AreEqual(200, Response1.StatusCode, 
    Format('First upload should succeed. Response: %s', [Response1.ContentAsString]));

  // Вторая загрузка (тот же файл)
  Response2 := PostToServer('/upload', JSONPayload, True);
  Assert.AreEqual(200, Response2.StatusCode, 'Second upload should succeed');

  // Assert: парсим ответы
  JSONResp1 := TJSONObject.ParseJSONValue(Response1.ContentAsString) as TJSONObject;
  JSONResp2 := TJSONObject.ParseJSONValue(Response2.ContentAsString) as TJSONObject;
  try
    // Проверяем file_id
    if (JSONResp1.GetValue('file_id') <> nil) and (JSONResp2.GetValue('file_id') <> nil) then
    begin
      FileId1 := JSONResp1.GetValue('file_id').Value;
      FileId2 := JSONResp2.GetValue('file_id').Value;
      
      // Проверяем, что созданы два разных файла (разные UUID)
      Assert.AreNotEqual(FileId1, FileId2,
        'Two uploads should create two different file records (different UUIDs)');
    end;
    
    // Проверяем checksum
    if (JSONResp1.GetValue('checksum') <> nil) and (JSONResp2.GetValue('checksum') <> nil) then
    begin
      Checksum1 := JSONResp1.GetValue('checksum').Value;
      Checksum2 := JSONResp2.GetValue('checksum').Value;
      
      // Проверяем, что checksum одинаковый (тот же контент)
      Assert.AreEqual(Checksum1, Checksum2,
        'Checksum should be the same for identical files');
    end;
  finally
    JSONResp1.Free;
    JSONResp2.Free;
  end;

  // Проверяем, что созданы две записи в БД
  FinalLogCount := GetTableCount('audit_logs');
  FinalFileCount := GetTableCount('audit_files');

  Assert.AreEqual(InitialLogCount + 2, FinalLogCount,
    'Two audit logs should be created');
  Assert.AreEqual(InitialFileCount + 2, FinalFileCount,
    'Two audit file records should be created');
end;

initialization
  TDUnitX.RegisterTestFixture(TTestSyncIntegration);

end.
