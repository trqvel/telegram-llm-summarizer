library(DBI)
library(RPostgres)

get_db_con <- function() {
  host   <- Sys.getenv("DB_HOST")
  port   <- Sys.getenv("DB_PORT", "5432")
  user   <- Sys.getenv("DB_USER")
  pass   <- Sys.getenv("DB_PASS")
  dbname <- Sys.getenv("DB_NAME")
  DBI::dbConnect(
    RPostgres::Postgres(),
    host     = host,
    port     = port,
    user     = user,
    password = pass,
    dbname   = dbname
  )
}
