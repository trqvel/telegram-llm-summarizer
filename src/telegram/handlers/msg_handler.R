library(jsonlite)
library(DBI)
source("src/db/connection_db.R")

con_local <- NULL

check_raw_msgs_table <- function(con) {
    table_exists <- dbExistsTable(con, "raw_msgs")
    if (!table_exists) {
        message("Таблица raw_msgs не существует. Создаем...")
        dbExecute(con, "
            CREATE TABLE raw_msgs (
                update_id BIGINT PRIMARY KEY,
                update_json TEXT,
                processed BOOLEAN DEFAULT FALSE,
                ts_insert TIMESTAMP DEFAULT NOW()
            )
        ")
        return(TRUE)
    }
    
    cols <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'raw_msgs'")
    has_processed_column <- "processed" %in% cols$column_name
    if (!has_processed_column) {
        message("Добавляем столбец processed в таблицу raw_msgs")
        tryCatch({
            dbExecute(con, "ALTER TABLE raw_msgs ADD COLUMN processed BOOLEAN DEFAULT FALSE")
            return(TRUE)
        }, error = function(e) {
            message(paste("ОШИБКА при добавлении столбца processed:", e$message))
            return(FALSE)
        })
    }
    
    return(TRUE)
}

msg_handler <- function(bot, update) {
    message(paste0("Получено обновление с ID: ", update$update_id))
    msg <- update$message
    if (is.null(msg) || is.null(msg$text)) {
        message("Обновление не содержит текстового сообщения, пропускаем")
        return()
    }
    
    message(paste0("Текст сообщения: ", msg$text))
    message(paste0("Чат ID: ", msg$chat$id))

    if (is.null(con_local) || !DBI::dbIsValid(con_local)) {
        message("Создаем новое подключение к БД")
        con_local <<- get_db_con()
        has_processed <- check_raw_msgs_table(con_local)
    }

    update_data <- list(
        update_id = update$update_id,
        message = list(
            message_id = msg$message_id,
            date = msg$date,
            text = msg$text,
            chat = list(
                id = msg$chat$id,
                type = msg$chat$type,
                title = msg$chat$title
            ),
            from = list(
                id = msg$from$id,
                is_bot = msg$from$is_bot,
                first_name = msg$from$first_name,
                username = msg$from$username
            )
        )
    )
    
    update_json <- tryCatch({
        toJSON(update_data, auto_unbox = TRUE)
    }, error = function(e) {
        message(paste("ОШИБКА при преобразовании в JSON:", e$message))
        return(NULL)
    })
    
    if (is.null(update_json)) {
        message("Пропуск вставки в БД из-за ошибки JSON")
        return()
    }
    
    message("Попытка вставки данных в БД")
    result <- tryCatch({
        cols <- dbGetQuery(con_local, "SELECT column_name FROM information_schema.columns WHERE table_name = 'raw_msgs'")
        has_processed_column <- "processed" %in% cols$column_name
        
        if (has_processed_column) {
            DBI::dbExecute(con_local,
                "INSERT INTO raw_msgs(update_id, update_json, processed)
                VALUES($1, $2, FALSE)
                ON CONFLICT (update_id) DO NOTHING",
                list(update$update_id, update_json)
            )
        } else {
            DBI::dbExecute(con_local,
                "INSERT INTO raw_msgs(update_id, update_json)
                VALUES($1, $2)
                ON CONFLICT (update_id) DO NOTHING",
                list(update$update_id, update_json)
            )
        }
        message(paste0("Запись успешно добавлена в БД, update_id: ", update$update_id))
        TRUE
    }, error = function(e) {
        message(paste0("ОШИБКА при записи в БД: ", e$message))
        FALSE
    })
}

handler <- MessageHandler(msg_handler)
dispatcher$add_handler(handler)

message("Обработчик сообщений запущен и готов к приему сообщений")
