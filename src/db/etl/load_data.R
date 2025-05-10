library(DBI)
library(RPostgres)
library(dplyr)
source("src/db/connection_db.R")

con <- get_db_con()

dbExecute(con, "
    CREATE TABLE IF NOT EXISTS processed_messages (
        update_id    BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
        processed_at TIMESTAMP DEFAULT NOW()
    )
")

new_msgs <- dbGetQuery(con, "
    SELECT update_id
    FROM clean_msgs
    WHERE update_id NOT IN (SELECT update_id FROM processed_messages)
")

if (nrow(new_msgs) > 0) {
    dbWriteTable(con, "processed_messages", new_msgs, append = TRUE)
}

dbDisconnect(con)
