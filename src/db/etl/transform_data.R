if (file.exists(".env")) readRenviron(".env")

library(DBI)
library(RPostgres)
library(dplyr)
library(jsonlite)
library(stringr)
library(stringi)
library(lubridate)
source("src/db/connection_db.R")

Sys.setlocale("LC_ALL", "en_US.UTF-8")

con <- get_db_con()

message("Этап трансформации: Проверка таблицы clean_msgs")
dbExecute(con, "
    CREATE TABLE IF NOT EXISTS clean_msgs (
        update_id   BIGINT PRIMARY KEY REFERENCES raw_msgs(update_id),
        chat_id     BIGINT,
        user_id     BIGINT,
        ts          TIMESTAMP,
        text_clean  TEXT
    )
")

message("Проверка структуры таблицы clean_msgs")
columns <- dbGetQuery(con, "
    SELECT column_name 
    FROM information_schema.columns 
    WHERE table_name = 'clean_msgs'
")

required_columns <- c('chat_title', 'user_name', 'text_raw')
for (col in required_columns) {
    if (!(col %in% columns$column_name)) {
        message(paste("Добавление отсутствующего столбца:", col))
        sql <- paste0("ALTER TABLE clean_msgs ADD COLUMN ", col, " TEXT")
        tryCatch({
            dbExecute(con, sql)
            message(paste("Столбец", col, "успешно добавлен"))
        }, error = function(e) {
            message(paste("ОШИБКА при добавлении столбца:", e$message))
        })
    }
}

message("Получение необработанных сообщений из raw_msgs")
raws <- dbGetQuery(con, "
    SELECT update_id, update_json
    FROM raw_msgs
    WHERE update_id NOT IN (SELECT update_id FROM clean_msgs)
    ORDER BY update_id
")

message(paste("Найдено", nrow(raws), "сообщений для трансформации"))

if (nrow(raws) > 0) {
    clean_list <- lapply(1:nrow(raws), function(i) {
        j <- raws$update_json[i]
        message(paste("Обработка сообщения", i, "из", nrow(raws), "- update_id:", raws$update_id[i]))
        
        tryCatch({
            j <- enc2utf8(j)
            u <- fromJSON(j)
            if (is.null(u$message)) {
                message("Не найден элемент message в JSON")
                return(NULL)
            }
            
            m <- u$message
            if (is.null(m$text)) {
                message("Не найден текст сообщения")
                return(NULL)
            }
            
            if (is.null(m$chat) || is.null(m$chat$id)) {
                message("Не найден ID чата")
                return(NULL)
            }
            
            message(paste("Текст сообщения:", enc2utf8(m$text)))
            
            chat_title <- NA
            if (!is.null(m$chat$title)) {
                chat_title <- enc2utf8(m$chat$title)
            }
            
            user_name <- NA
            if (!is.null(m$from$username)) {
                user_name <- enc2utf8(m$from$username)
            } else if (!is.null(m$from$first_name)) {
                user_name <- enc2utf8(m$from$first_name)
            }
            
            text_raw <- enc2utf8(m$text)
            text_clean <- str_squish(
                stringi::stri_replace_all_regex(
                    str_remove_all(str_remove_all(text_raw, "<[^>]+>"), "https?://\\S+"),
                    "\\p{Emoji}", ""
                )
            )
            
            data.frame(
                update_id  = u$update_id,
                chat_id    = m$chat$id,
                chat_title = chat_title,
                user_id    = m$from$id,
                user_name  = user_name,
                ts         = as_datetime(m$date),
                text_raw   = text_raw,
                text_clean = text_clean,
                stringsAsFactors = FALSE
            )
        }, error = function(e) {
            message(paste("ОШИБКА при обработке JSON:", e$message))
            message(paste("Проблемный JSON:", substr(j, 1, 100), "..."))
            NULL
        })
    })

    clean_list <- Filter(Negate(is.null), clean_list)
    
    if (length(clean_list) > 0) {
        message(paste("Успешно преобразовано", length(clean_list), "сообщений"))
        clean_df <- bind_rows(clean_list)
        
        tryCatch({
            dbExecute(con, "SET client_encoding = 'UTF8'")
            dbWriteTable(con, "clean_msgs", clean_df, append = TRUE)
            message("Данные успешно записаны в таблицу clean_msgs")
            
            dbExecute(con, "
                UPDATE raw_msgs
                SET processed = TRUE
                WHERE update_id IN (
                    SELECT update_id FROM clean_msgs
                )
            ")
            message("Обновлены флаги processed в таблице raw_msgs")
        }, error = function(e) {
            message(paste("ОШИБКА при записи в БД:", e$message))
        })
    } else {
        message("Нет данных для записи в clean_msgs")
    }
} else {
    message("Нет новых сообщений для обработки")
}

dbDisconnect(con)
message("Этап трансформации завершен")
