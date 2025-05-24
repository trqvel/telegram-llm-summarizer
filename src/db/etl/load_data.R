library(DBI)
library(RPostgres)
source("src/db/connection_db.R")

message("--- Начало ETL: загрузка данных ---")

tryCatch({
  con <- get_db_con()

  message("Проверка таблицы processed_messages")
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS processed_messages (
        update_id    BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
        processed_at TIMESTAMP DEFAULT NOW()
    )
  ")

  message("Получение списка необработанных сообщений для загрузки")
  unprocessed <- dbGetQuery(con, "
    SELECT update_id 
    FROM clean_msgs 
    WHERE update_id NOT IN (SELECT update_id FROM processed_messages)
  ")

  message(paste("Найдено", nrow(unprocessed), "сообщений для обработки"))

  if (nrow(unprocessed) > 0) {
    message("Вставка новых записей в processed_messages")
    
    success_count <- 0
    for (i in 1:nrow(unprocessed)) {
      tryCatch({
        result <- dbExecute(con, "
          INSERT INTO processed_messages(update_id)
          VALUES($1)
          ON CONFLICT DO NOTHING
        ", params = list(unprocessed$update_id[i]))
        
        if (result > 0) {
          success_count <- success_count + 1
          message(paste("Успешно обработано сообщение с update_id:", unprocessed$update_id[i]))
        }
      }, error = function(e) {
        message(paste("ОШИБКА при обработке update_id", unprocessed$update_id[i], ":", e$message))
      })
    }
    
    message(paste("Успешно загружено", success_count, "из", nrow(unprocessed), "сообщений"))
  } else {
    message("Нет новых сообщений для загрузки")
  }

  message("Обновление статистики в БД")
  tryCatch({
    dbExecute(con, "ANALYZE processed_messages")
    dbExecute(con, "ANALYZE clean_msgs")
    dbExecute(con, "ANALYZE raw_msgs")
    message("Статистика обновлена")
  }, error = function(e) {
    message(paste("ОШИБКА при обновлении статистики:", e$message))
  })

  dbDisconnect(con)
  message("--- Конец ETL: загрузка данных ---")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле load_data.R:", e$message))
  print(traceback())
})
