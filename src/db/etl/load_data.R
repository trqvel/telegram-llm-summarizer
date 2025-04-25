library(DBI)
library(RPostgres)
library(dplyr)

source("src/db/connection.R")
con <- get_db_con()

new_messages <- dbGetQuery(con, "
  SELECT *
  FROM clean_msgs
  WHERE update_id > COALESCE(
    (SELECT MAX(update_id) FROM processed_messages),
    0
  )
  ORDER BY ts
")

if (!dbExistsTable(con, "processed_messages")) {
  dbExecute(con, "
    CREATE TABLE processed_messages (
      update_id   BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
      processed_at TIMESTAMP DEFAULT NOW()
    )
  ")
}

if (nrow(new_messages) > 0) {
  processed_ids <- data.frame(
    update_id = new_messages$update_id
  )
  dbWriteTable(con, "processed_messages", processed_ids, append = TRUE)
  cat(sprintf("Загружено %d новых сообщений\n", nrow(new_messages)))
} else {
  cat("Новых сообщений не найдено\n")
}

dbDisconnect(con)
