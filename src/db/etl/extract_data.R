if (file.exists(".env")) {
  readRenviron(".env")
}

library(telegram.bot)
library(jsonlite)

source("src/db/connection.R")
con <- get_db_con()

if (!dbExistsTable(con, "raw_updates")) {
  dbExecute(con, "
    CREATE TABLE raw_updates (
      update_id   BIGINT PRIMARY KEY,
      update_json JSONB,
      ts_insert   TIMESTAMP DEFAULT NOW()
    )"
  )
}

last_id <- dbGetQuery(con, "
  SELECT COALESCE(MAX(update_id), 0) AS id
  FROM raw_updates
")$id

bot <- Bot(token = Sys.getenv("TELEGRAM_BOT_TOKEN"))
updates <- bot$getUpdates(offset = last_id + 1, timeout = 30)

if (length(updates) > 0) {
  for (u in updates) {
    dbExecute(con, "
      INSERT INTO raw_updates(update_id, update_json)
      VALUES($1, $2)
      ON CONFLICT DO NOTHING
    ", list(u$update_id, toJSON(u, auto_unbox = TRUE)))
  }
}

dbDisconnect(con)
