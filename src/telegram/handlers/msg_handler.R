library(jsonlite)
library(DBI)
source("src/db/connection_db.R")

con_local <- NULL

msg_handler <- function(bot, update) {
    msg <- update$message
    if (is.null(msg) || is.null(msg$text)) return()

    if (is.null(con_local) || !DBI::dbIsValid(con_local)) {
        con_local <<- get_db_con()
    }

    u <- update
    DBI::dbExecute(con_local,
        "INSERT INTO raw_msgs(update_id, update_json)
         VALUES($1, $2)
         ON CONFLICT DO NOTHING",
        list(u$update_id, toJSON(u, auto_unbox = TRUE))
    )
}

handler <- MessageHandler(msg_handler)
dispatcher$add_handler(handler)
