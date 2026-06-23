unit ServerSessionContext;

interface

// объявляем потоковую переменную.
// У каждого HTTP-запроса (потока) будет свое собственное, изолированное значение.
threadvar
  CurrentUserID: Int64;

implementation

end.
