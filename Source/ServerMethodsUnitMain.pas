unit ServerMethodsUnitMain;

interface

uses System.SysUtils, System.Classes, System.Json,
    DataSnap.DSProviderDataModuleAdapter, System.Generics.Collections,
    Datasnap.DSServer, Datasnap.DSAuth, FireDAC.UI.Intf, FireDAC.VCLUI.Login,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Phys.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys,
  FireDAC.Phys.PG, FireDAC.Phys.PGDef, FireDAC.VCLUI.Wait, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, FireDAC.Comp.UI, System.IOUtils, Data.DBXJSONReflect;

type
  TServerMethods1 = class(TDSServerModule)
    PGConn: TFDConnection;
    qryInsert: TFDQuery;
    procedure DSServerModuleCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    function EchoString(Value: string): string;
    function ReverseString(Value: string): string;
    function updateSyncUpload(const AJsonData: string): string;
  end;

implementation


{$R *.dfm}


uses System.StrUtils;

procedure TServerMethods1.DSServerModuleCreate(Sender: TObject);
begin
  PGConn.ConnectionName := 'PgServerConn';
  PGConn.LoginPrompt := False;
end;

function TServerMethods1.EchoString(Value: string): string;
begin
  Result := Value;
end;

function TServerMethods1.ReverseString(Value: string): string;
begin
  Result := System.StrUtils.ReverseString(Value);
end;

function TServerMethods1.updateSyncUpload(const AJsonData: string): string;
var
  RootVal, InnerVal: TJSONValue;
  Arr: TJSONArray;
  I: Integer;
  Item, Details: TJSONObject;
begin
  // 1. Первичный парсинг входящей строки
  RootVal := TJSONObject.ParseJSONValue(AJsonData);
  if not Assigned(RootVal) then Exit('{"result":"error","message":"Invalid JSON root"}');

  // 2. Извлекаем значение по ключу "AJsonData" (если пришла обёртка {"AJsonData":"..."})
  if RootVal is TJSONObject then
    InnerVal := TJSONObject(RootVal).GetValue('AJsonData')
  else
    InnerVal := RootVal;

  // 3. Если внутри строка (ваш случай), парсим её ещё раз
  if InnerVal is TJSONString then
    RootVal := TJSONObject.ParseJSONValue(TJSONString(InnerVal).Value)
  else
    RootVal := InnerVal;

  // 4. Приводим к массиву
  if not (RootVal is TJSONArray) then
    Exit('{"result":"error","message":"Expected JSON array"}');

  Arr := TJSONArray(RootVal);
  if Arr.Count = 0 then Exit('{"result":"ok","count":0}');

  // 5. Вставка в БД (ваша логика без изменений)
  try
    PGConn.Open;
    PGConn.StartTransaction;
    try
      for I := 0 to Arr.Count - 1 do
      begin
        Item := Arr.Items[I] as TJSONObject;
        Details := Item.GetValue('details') as TJSONObject;

        qryInsert.SQL.Text :=
          'INSERT INTO events (user_id, event_type, occurred_at, metadata) ' +
          'VALUES (:uid, :etype, :otime, :meta::jsonb)';

        qryInsert.ParamByName('uid').AsInteger := Item.GetValue('user_id', 1);
        qryInsert.ParamByName('etype').AsString := Item.GetValue('event_type', 'mobile_audit');
        qryInsert.ParamByName('otime').AsDateTime := Now;
        qryInsert.ParamByName('meta').AsString := Details.ToString;
        qryInsert.ExecSQL;
      end;
      PGConn.Commit;
      Result := '{"result":"ok","count":' + IntToStr(Arr.Count) + '}';
    except
      on E: Exception do begin PGConn.Rollback; raise; end;
    end;
  except
    on E: Exception do
      Result := '{"result":"error","message":"' + StringReplace(E.Message, '"', '\"', [rfReplaceAll]) + '"}';
  end;
end;

end.

