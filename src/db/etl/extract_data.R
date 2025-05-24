library(DBI)
library(RPostgres)
library(jsonlite)
library(telegram.bot)
source("src/db/connection_db.R")

message("--- Начало ETL: извлечение данных ---")

con <- get_db_con()

message("Проверка существования таблицы raw_msgs")
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
  message("Таблица raw_msgs создана.")
} else {
  cols <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'raw_msgs'")
  if (!"processed" %in% cols$column_name) {
    message("Добавляем столбец processed в таблицу raw_msgs")
    tryCatch({
      dbExecute(con, "ALTER TABLE raw_msgs ADD COLUMN processed BOOLEAN DEFAULT FALSE")
      message("Столбец processed успешно добавлен")
    }, error = function(e) {
      message(paste("ОШИБКА при добавлении столбца processed:", e$message))
    })
  }
}

message("Запрашиваем необработанные сообщения")
pending <- dbGetQuery(con, "
  SELECT update_id, update_json 
  FROM raw_msgs 
  WHERE processed = FALSE OR processed IS NULL
  LIMIT 100
")

message(paste("Найдено", nrow(pending), "необработанных сообщений"))

if (nrow(pending) > 0) {
  message("Начинаем парсинг JSON данных из необработанных сообщений")
  
  raw_data <- list()
  for (i in seq_len(nrow(pending))) {
    p <- pending[i, ]
    message(paste("Обработка update_id:", p$update_id))
    
    json_data <- tryCatch({
      fromJSON(p$update_json)
    }, error = function(e) {
      message(paste("Ошибка парсинга JSON для update_id", p$update_id, ":", e$message))
      message(paste("Проблемный JSON:", substr(p$update_json, 1, 100), "..."))
      NULL
    })
    
    if (!is.null(json_data)) {
      message(paste("JSON успешно распаршен для update_id:", p$update_id))
      raw_data[[length(raw_data) + 1]] <- json_data
    }
  }
  
  message(paste("Успешно распаршено:", length(raw_data), "сообщений"))
} else {
  message("Нет необработанных сообщений для извлечения")
}

dbDisconnect(con)

message("--- Конец ETL: извлечение данных ---")
