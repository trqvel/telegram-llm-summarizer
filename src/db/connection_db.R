library(DBI)
library(RPostgres)

get_db_con <- function() {
  host   <- Sys.getenv("DB_HOST")
  port   <- Sys.getenv("DB_PORT", "5432")
  user   <- Sys.getenv("DB_USER")
  pass   <- Sys.getenv("DB_PASS")
  dbname <- Sys.getenv("DB_NAME")
  
  if (nchar(host) == 0 || nchar(user) == 0 || nchar(pass) == 0 || nchar(dbname) == 0) {
    stop("Отсутствуют необходимые параметры подключения к БД. Проверьте переменные окружения.")
  }
  
  message(paste("Подключение к БД:", user, "@", host, ":", port, "/", dbname))
  
  con <- DBI::dbConnect(
    RPostgres::Postgres(),
    host     = host,
    port     = port,
    user     = user,
    password = pass,
    dbname   = dbname,
    options  = "-c client_encoding=UTF8"
  )
  
  DBI::dbExecute(con, "SET client_encoding = 'UTF8'")
  DBI::dbExecute(con, "SET names 'UTF8'")
  
  message("Подключение к БД успешно установлено")
  return(con)
}
