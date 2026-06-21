object frmServer: TfrmServer
  Left = 271
  Top = 114
  Caption = 'DataSnap Server'
  ClientHeight = 235
  ClientWidth = 399
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object Label1: TLabel
    Left = 24
    Top = 48
    Width = 20
    Height = 13
    Caption = 'Port'
  end
  object ButtonStart: TButton
    Left = 24
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Start'
    TabOrder = 0
    OnClick = ButtonStartClick
  end
  object ButtonStop: TButton
    Left = 105
    Top = 8
    Width = 75
    Height = 25
    Caption = 'Stop'
    TabOrder = 1
    OnClick = ButtonStopClick
  end
  object EditPort: TEdit
    Left = 24
    Top = 67
    Width = 121
    Height = 21
    TabOrder = 2
    Text = '8082'
  end
  object ButtonOpenBrowser: TButton
    Left = 24
    Top = 112
    Width = 107
    Height = 25
    Caption = 'Open Browser'
    TabOrder = 3
    Visible = False
    OnClick = ButtonOpenBrowserClick
  end
  object ApplicationEvents1: TApplicationEvents
    OnIdle = ApplicationEvents1Idle
    Left = 288
    Top = 24
  end
  object FDManager1: TFDManager
    FormatOptions.AssignedValues = [fvMapRules]
    FormatOptions.OwnMapRules = True
    FormatOptions.MapRules = <>
    Active = True
    Left = 212
    Top = 100
  end
  object StartConn: TFDConnection
    Params.Strings = (
      'Server=localhost'
      'Database=postgres'
      'User_Name=postgres'
      'DriverID=PG'
      'Port=5432'
      'Pooled=False'
      'POOL_MaximumItems=10')
    ResourceOptions.AssignedValues = [rvSilentMode]
    ResourceOptions.SilentMode = True
    TxOptions.AutoStop = False
    LoginPrompt = False
    Left = 56
    Top = 160
  end
  object qryClearSession: TFDQuery
    Connection = StartConn
    SQL.Strings = (
      'DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;')
    Left = 136
    Top = 160
  end
  object tmrCheckSessions: TTimer
    Interval = 1800
    OnTimer = tmrCheckSessionsTimer
    Left = 284
    Top = 164
  end
end
