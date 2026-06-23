program IntegrationTests;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  TestBase in 'TestBase.pas',
  TestLoginIntegration in 'TestLoginIntegration.pas',
  TestUploadIntegration in 'TestUploadIntegration.pas',
  TestSyncIntegration in 'TestSyncIntegration.pas',
  TestSecurityIntegration in 'TestSecurityIntegration.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  logger: ITestLogger;
  nunitLogger : ITestLogger;
begin
  ReportMemoryLeaksOnShutdown := True;

  WriteLn('========================================');
  WriteLn('  Integration Tests for Audit Server');
  WriteLn('========================================');
  WriteLn;
  WriteLn('Требования:');
  WriteLn('1. Docker Desktop запущен');
  WriteLn('2. Тестовая БД запущена: docker-compose -f docker-compose.test.yml up -d');
  WriteLn('3. DataSnap Server запущен на http://localhost:8082');
  WriteLn;

  try
{
    // 🔑 ИСПРАВЛЕНИЕ: Используем правильный API DUnitX
    // 1. Регистрируем консольный логгер
    TDUnitX.RegisterLogger(TDUnitXConsoleLogger.Create(True));

    // 2. Регистрируем XML NUnit логгер
    LogStream := TFileStream.Create(
      ExtractFilePath(ParamStr(0)) + 'integration-test-results.xml',
      fmCreate);
    TDUnitX.RegisterLogger(TDUnitXXMLNUnitLogger.Create(LogStream));
}
    // 3. Создаём runner
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;

    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
    begin
      logger := TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet);
      runner.AddLogger(logger);
    end;
    //Generate an NUnit compatible XML File
    nunitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    runner.AddLogger(nunitLogger);
    // 4. Запускаем тесты
    WriteLn('Запуск тестов...');
    WriteLn;
    Results := Runner.Execute;

    // 5. Устанавливаем код выхода
    if not Results.AllPassed then
    begin
      WriteLn;
      WriteLn('❌ НЕКОТОРЫЕ ТЕСТЫ ПРОВАЛЕНЫ!');
      System.ExitCode := 1;
    end
    else
    begin
      WriteLn;
      WriteLn('✅ ВСЕ ТЕСТЫ ПРОЙДЕНЫ УСПЕШНО!');
      System.ExitCode := 0;
    end;

    WriteLn;
    WriteLn('Результаты сохранены в: dunitx-results.xml');
    WriteLn('Press Enter to exit...');
    ReadLn;
  except
    on E: Exception do
    begin
      WriteLn;
      WriteLn('❌ ОШИБКА: ', E.Message);
      System.ExitCode := 1;
    end;
  end;
end.
