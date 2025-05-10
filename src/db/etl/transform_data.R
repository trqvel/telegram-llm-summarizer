library(DBI)
library(RPostgres)
library(dplyr)
library(jsonlite)
library(stringr)
library(lubridate)
source("src/db/connection_db.R")

con <- get_db_con()

dbExecute(con, "
    CREATE TABLE IF NOT EXISTS clean_msgs (
        update_id   BIGINT PRIMARY KEY REFERENCES raw_msgs(update_id),
        chat_id     BIGINT,
        chat_title  TEXT,
        user_id     BIGINT,
        user_name   TEXT,
        ts          TIMESTAMP,
        text_raw    TEXT,
        text_clean  TEXT
    )
")

raws <- dbGetQuery(con, "
    SELECT update_id, update_json
    FROM raw_msgs
    WHERE update_id NOT IN (SELECT update_id FROM clean_msgs)
")

if (nrow(raws) > 0) {
    clean_list <- lapply(raws$update_json, function(j) {
        u <- fromJSON(j)
        m <- u$message
        if (is.null(m$text)) return(NULL)
        data.frame(
            update_id  = u$update_id,
            chat_id    = m$chat$id,
            chat_title = ifelse(is.null(m$chat$title), NA, m$chat$title),
            user_id    = m$from$id,
            user_name  = ifelse(is.null(m$from$username), m$from$first_name, m$from$username),
            ts         = as_datetime(m$date),
            text_raw   = m$text,
            text_clean = str_squish(
                str_remove_all(str_remove_all(m$text, "<[^>]+>"), "https?://\\S+")
            ),
            stringsAsFactors = FALSE
        )
    })

    clean_list <- Filter(Negate(is.null), clean_list)
    clean_df   <- bind_rows(clean_list)

    dbWriteTable(con, "clean_msgs", clean_df, append = TRUE)
}

dbDisconnect(con)
