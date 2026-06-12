object ServerMethods1: TServerMethods1
  OnCreate = DSServerModuleCreate
  Height = 480
  Width = 640
  object PGConn: TFDConnection
    Params.Strings = (
      'Server=localhost'
      'Database=postgres'
      'User_Name=postgres'
      'DriverID=PG'
      'Port=5432'
      'Pooled=False'
      'POOL_MaximumItems=10')
    TxOptions.AutoStop = False
    LoginPrompt = False
    Left = 48
    Top = 12
  end
  object qryInsert: TFDQuery
    Connection = PGConn
    SQL.Strings = (
      'INSERT INTO events (user_id, event_type, occurred_at, metadata)'
      'VALUES (:uid, :etype, :otime, :meta::jsonb)')
    Left = 148
    Top = 12
    ParamData = <
      item
        Name = 'UID'
        DataType = ftInteger
        FDDataType = dtInt32
        ParamType = ptInput
      end
      item
        Name = 'ETYPE'
        DataType = ftString
        FDDataType = dtWideString
        ParamType = ptInput
      end
      item
        Name = 'OTIME'
        DataType = ftDateTime
        FDDataType = dtDateTime
        ParamType = ptInput
      end
      item
        Name = 'META'
        DataType = ftString
        FDDataType = dtWideString
        ParamType = ptInput
      end>
  end
end
