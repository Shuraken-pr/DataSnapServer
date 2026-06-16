object frmServerSettings: TfrmServerSettings
  Left = 0
  Top = 0
  Caption = #1053#1072#1089#1090#1088#1086#1081#1082#1080' '#1089#1086#1077#1076#1080#1085#1077#1085#1080#1103
  ClientHeight = 278
  ClientWidth = 475
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 15
  object lcConnectionSettings: TdxLayoutControl
    Left = 0
    Top = 0
    Width = 475
    Height = 278
    Align = alClient
    TabOrder = 0
    ExplicitHeight = 226
    object edPort: TcxSpinEdit
      Left = 85
      Top = 42
      Properties.MaxValue = 65535.000000000000000000
      Properties.MinValue = 1.000000000000000000
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      Style.ButtonStyle = bts3D
      TabOrder = 1
      Value = 5432
      Width = 378
    end
    object edPassword: TcxTextEdit
      Left = 85
      Top = 132
      Properties.EchoMode = eemPassword
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      TabOrder = 4
      Width = 378
    end
    object btnOk: TBitBtn
      Left = 359
      Top = 241
      Width = 104
      Height = 25
      Caption = 'OK'
      Default = True
      NumGlyphs = 2
      TabOrder = 8
      OnClick = btnOkClick
    end
    object edLogin: TcxTextEdit
      Left = 85
      Top = 102
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      TabOrder = 3
      Width = 378
    end
    object edDatabase: TcxTextEdit
      Left = 85
      Top = 72
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      TabOrder = 2
      Text = 'postgres'
      Width = 378
    end
    object edServer: TcxTextEdit
      Left = 85
      Top = 12
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      TabOrder = 0
      Text = 'localhost'
      Width = 378
    end
    object btnTest: TButton
      Left = 12
      Top = 241
      Width = 113
      Height = 25
      Caption = #1058#1077#1089#1090' '#1089#1086#1077#1076#1080#1085#1077#1085#1080#1103
      TabOrder = 6
      OnClick = btnTestClick
    end
    object edApiKey: TcxTextEdit
      Left = 85
      Top = 162
      Style.BorderColor = clWindowFrame
      Style.BorderStyle = ebs3D
      Style.HotTrack = False
      Style.TransparentBorder = False
      TabOrder = 5
      Width = 378
    end
    object btnGenerateApiKey: TButton
      Left = 132
      Top = 241
      Width = 161
      Height = 25
      Caption = #1057#1075#1077#1085#1077#1088#1080#1088#1086#1074#1072#1090#1100' API '#1082#1083#1102#1095
      TabOrder = 7
      OnClick = btnGenerateApiKeyClick
    end
    object lcConnectionSettingsGroup_Root: TdxLayoutGroup
      AlignHorz = ahClient
      AlignVert = avClient
      Hidden = True
      ShowBorder = False
      Index = -1
    end
    object liPort: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avTop
      CaptionOptions.Text = #1055#1086#1088#1090
      Control = edPort
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 1
    end
    object liPassword: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avTop
      CaptionOptions.Text = #1055#1072#1088#1086#1083#1100
      Control = edPassword
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 4
    end
    object lgAction: TdxLayoutGroup
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avBottom
      CaptionOptions.Text = 'New Group'
      LayoutDirection = ldHorizontal
      ShowBorder = False
      Index = 6
    end
    object liOk: TdxLayoutItem
      Parent = lgAction
      AlignHorz = ahRight
      AlignVert = avClient
      CaptionOptions.Text = 'BitBtn1'
      CaptionOptions.Visible = False
      Control = btnOk
      ControlOptions.OriginalHeight = 25
      ControlOptions.OriginalWidth = 104
      ControlOptions.ShowBorder = False
      Index = 2
    end
    object liLogin: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avTop
      CaptionOptions.Text = #1051#1086#1075#1080#1085
      Control = edLogin
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 3
    end
    object liDatabase: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avTop
      CaptionOptions.Text = #1041#1072#1079#1072' '#1076#1072#1085#1085#1099#1093
      Control = edDatabase
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 2
    end
    object liServer: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      AlignHorz = ahClient
      AlignVert = avTop
      CaptionOptions.Text = #1057#1077#1088#1074#1077#1088
      Control = edServer
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 0
    end
    object liTest: TdxLayoutItem
      Parent = lgAction
      AlignHorz = ahLeft
      AlignVert = avClient
      CaptionOptions.Text = 'Button1'
      CaptionOptions.Visible = False
      Control = btnTest
      ControlOptions.OriginalHeight = 25
      ControlOptions.OriginalWidth = 113
      ControlOptions.ShowBorder = False
      Index = 0
    end
    object liApiKey: TdxLayoutItem
      Parent = lcConnectionSettingsGroup_Root
      CaptionOptions.Text = 'API '#1082#1083#1102#1095
      Control = edApiKey
      ControlOptions.OriginalHeight = 23
      ControlOptions.OriginalWidth = 121
      ControlOptions.ShowBorder = False
      Index = 5
    end
    object dxLayoutItem1: TdxLayoutItem
      Parent = lgAction
      CaptionOptions.Text = 'Button1'
      CaptionOptions.Visible = False
      Control = btnGenerateApiKey
      ControlOptions.OriginalHeight = 25
      ControlOptions.OriginalWidth = 161
      ControlOptions.ShowBorder = False
      Index = 1
    end
  end
end
