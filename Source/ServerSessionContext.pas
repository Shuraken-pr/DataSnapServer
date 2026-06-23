unit ServerSessionContext;

interface

// объявляем потоковые переменные.
// У каждого HTTP-запроса (потока) будет свое собственное, изолированное значение.
threadvar
  CurrentUserID: Int64;
  CurrentIP: string;

implementation

end.
