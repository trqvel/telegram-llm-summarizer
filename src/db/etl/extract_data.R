if (file.exists(".env")) {
    readRenviron(".env")
}

library(DBI)
library(RPostgres)
library(jsonlite)
library(telegram.bot)
source("src/db/connection.R")

con <- get_db_con()

dbExecute(con, "
    CREATE TABLE IF NOT EXISTS raw_msgs (
        update_id   BIGINT PRIMARY KEY,
        update_json JSONB,
        ts_insert   TIMESTAMP DEFAULT NOW()
    )
")

last_id <- dbGetQuery(con, "
    SELECT COALESCE(MAX(update_id), 0) AS id
    FROM raw_msgs
")$id

bot     <- Bot(token = Sys.getenv("TELEGRAM_BOT_TOKEN"))
updates <- bot$getUpdates(offset = last_id + 1, timeout = 30)

if (length(updates) > 0) {
    for (u in updates) {
        dbExecute(con, "
            INSERT INTO raw_msgs(update_id, update_json)
            VALUES($1, $2)
            ON CONFLICT DO NOTHING
        ", list(u$update_id, toJSON(u, auto_unbox = TRUE)))
    }
}

dbDisconnect(con)
