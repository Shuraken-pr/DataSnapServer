unit ServerLogger;

interface

uses
  LoggerPro;

/// <summary>Возвращает настроенный экземпляр логгера для использования во всем приложении.</summary>
function Log: ILogWriter;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  LoggerPro.Builder,
  LoggerPro.FileAppender;

var
  _Log: ILogWriter;
  LogPath: string;

function Log: ILogWriter;
begin
  Result := _Log;
end;

initialization
  // Формируем путь: папка с exe-файлом + подпапка 'logs'
  LogPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
  TDirectory.CreateDirectory(LogPath);

  // Настраиваем логгер через Fluent Builder API (используем реальные методы из LoggerPro.Builder)
  _Log := LoggerProBuilder
    .WithDefaultMinimumLevel(TLogType.Info) // Записывать Info и выше (Warning, Error, Fatal)
    .WriteToFile
      .WithLogsFolder(LogPath)
      .WithFileBaseName('DataSnapServer')
      .WithMaxBackupFiles(15)               // Хранить последние 15 файлов (ротация)
      .WithMaxFileSizeInKB(10240)           // Ротация при достижении 10 МБ (10 * 1024 КБ)
      .Done
    .Build;

finalization
  // Корректное завершение работы логгера (сброс буферов в файл перед закрытием приложения)
  if Assigned(_Log) then
    _Log.Shutdown;

end.
