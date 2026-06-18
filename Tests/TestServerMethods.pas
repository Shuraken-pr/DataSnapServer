unit TestServerMethods;

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  System.Generics.Collections,
  System.SysUtils;

type
  [TestFixture]
  TTestJsonParsing = class
  public
    [Test]
    procedure TestParseValidJsonArray;
    
    [Test]
    procedure TestParseJsonWithWrapper;
    
    [Test]
    procedure TestParseInvalidJson;
    
    [Test]
    procedure TestParseEmptyArray;
    
    [Test]
    procedure TestParseJsonWithMissingFields;
    
    [Test]
    procedure TestParseJsonStringWrapper;
  end;

implementation

procedure TTestJsonParsing.TestParseValidJsonArray;
var
  JsonStr: string;
  RootVal: TJSONValue;
  Arr: TJSONArray;
begin
  JsonStr := '[{"event_type":"mobile_audit","details":{"lat":55.75,"lon":37.62}}]';
  RootVal := TJSONObject.ParseJSONValue(JsonStr);
  
  Assert.IsNotNull(RootVal, 'JSON должен успешно распарситься');
  Assert.IsTrue(RootVal is TJSONArray, 'Корневой элемент должен быть массивом');
  
  Arr := TJSONArray(RootVal);
  Assert.AreEqual(1, Arr.Count, 'Массив должен содержать 1 элемент');
  
  RootVal.Free;
end;

procedure TTestJsonParsing.TestParseJsonWithWrapper;
var
  JsonStr: string;
  RootVal, InnerVal: TJSONValue;
  Arr: TJSONArray;
begin
  JsonStr := '{"AJsonData":[{"event_type":"mobile_audit"}]}';
  RootVal := TJSONObject.ParseJSONValue(JsonStr);
  
  Assert.IsNotNull(RootVal, 'JSON должен успешно распарситься');
  Assert.IsTrue(RootVal is TJSONObject, 'Корневой элемент должен быть объектом');
  
  InnerVal := TJSONObject(RootVal).GetValue('AJsonData');
  Assert.IsNotNull(InnerVal, 'Поле AJsonData должно существовать');
  Assert.IsTrue(InnerVal is TJSONArray, 'AJsonData должен быть массивом');
  
  Arr := TJSONArray(InnerVal);
  Assert.AreEqual(1, Arr.Count, 'Массив должен содержать 1 элемент');
  
  RootVal.Free;
end;

procedure TTestJsonParsing.TestParseInvalidJson;
var
  RootVal: TJSONValue;
begin
  RootVal := TJSONObject.ParseJSONValue('invalid json {{{');
  Assert.IsNull(RootVal, 'Невалидный JSON должен вернуть nil');
end;

procedure TTestJsonParsing.TestParseEmptyArray;
var
  JsonStr: string;
  RootVal: TJSONValue;
  Arr: TJSONArray;
begin
  JsonStr := '[]';
  RootVal := TJSONObject.ParseJSONValue(JsonStr);
  
  Assert.IsNotNull(RootVal, 'Пустой массив должен распарситься');
  Assert.IsTrue(RootVal is TJSONArray, 'Должен быть массивом');
  
  Arr := TJSONArray(RootVal);
  Assert.AreEqual(0, Arr.Count, 'Массив должен быть пустым');
  
  RootVal.Free;
end;

procedure TTestJsonParsing.TestParseJsonWithMissingFields;
var
  JsonStr: string;
  RootVal: TJSONValue;
  Arr: TJSONArray;
  Item: TJSONObject;
begin
  JsonStr := '[{"event_type":"mobile_audit"}]'; // Нет details
  RootVal := TJSONObject.ParseJSONValue(JsonStr);
  
  Arr := TJSONArray(RootVal);
  Item := Arr.Items[0] as TJSONObject;
  
  Assert.IsNotNull(Item.GetValue('event_type'), 'event_type должен существовать');
  Assert.IsNull(Item.GetValue('details'), 'details может отсутствовать');
  
  RootVal.Free;
end;

procedure TTestJsonParsing.TestParseJsonStringWrapper;
var
  JsonStr: string;
  RootVal, InnerVal: TJSONValue;
  InnerStr: string;
  ParsedInner: TJSONValue;
begin
  // Формат, где AJsonData — это строка с экранированным JSON
  JsonStr := '{"AJsonData":"[{\"event_type\":\"mobile_audit\"}]"}';
  RootVal := TJSONObject.ParseJSONValue(JsonStr);
  
  Assert.IsNotNull(RootVal, 'JSON должен успешно распарситься');
  Assert.IsTrue(RootVal is TJSONObject, 'Корневой элемент должен быть объектом');
  
  InnerVal := TJSONObject(RootVal).GetValue('AJsonData');
  Assert.IsNotNull(InnerVal, 'Поле AJsonData должно существовать');
  Assert.IsTrue(InnerVal is TJSONString, 'AJsonData должен быть строкой');
  
  // Парсим внутреннюю строку
  InnerStr := TJSONString(InnerVal).Value;
  ParsedInner := TJSONObject.ParseJSONValue(InnerStr);
  
  Assert.IsNotNull(ParsedInner, 'Внутренний JSON должен распарситься');
  Assert.IsTrue(ParsedInner is TJSONArray, 'Внутренний элемент должен быть массивом');
  
  RootVal.Free;
  ParsedInner.Free;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestJsonParsing);

end.
