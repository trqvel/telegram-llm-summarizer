library(DBI)
library(dplyr)
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

message("Запуск модуля анализа тональности сообщений")

tryCatch({
  con <- get_db_con()

  dbExecute(con,"
    CREATE TABLE IF NOT EXISTS sentiments(
      update_id BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
      sentiment TEXT
    )
  ")

  pending <- dbGetQuery(con,"
    SELECT update_id, text_clean
    FROM clean_msgs
    WHERE update_id NOT IN (SELECT update_id FROM sentiments)
    LIMIT 50  -- Ограничиваем количество обрабатываемых сообщений за раз
  ")

  message(paste("Найдено", nrow(pending), "сообщений для анализа тональности"))

  if (nrow(pending) > 0) {
    success_count <- 0
    
    for (i in seq_len(nrow(pending))) {
      p <- pending[i, ]
      
      message(paste("Обработка сообщения", i, "из", nrow(pending), 
                   "- update_id:", p$update_id))
      
      if (nchar(p$text_clean) < 5) {
        message(paste("Сообщение слишком короткое, пропускаем:", p$text_clean))
        dbExecute(con, "
          INSERT INTO sentiments(update_id, sentiment) 
          VALUES($1, $2) 
          ON CONFLICT DO NOTHING
        ", params = list(p$update_id, 'нейтральная'))
        next
      }
      
      prompt <- paste(
        "Определи тональность этого сообщения:",
        "положительная, отрицательная или нейтральная.",
        p$text_clean,
        sep = "\n\n"
      )
      
      tryCatch({
        message("Вызов Llama API для определения тональности...")
        sentiment <- tolower(hf_complete(prompt, max_tokens = 16))
        message(paste("Получен результат:", sentiment))
        
        if (grepl("положит", sentiment)) {
          sentiment_value <- "положительная"
        } else if (grepl("отриц|негатив", sentiment)) {
          sentiment_value <- "отрицательная" 
        } else {
          sentiment_value <- "нейтральная"
        }
        
        message(paste("Итоговая тональность:", sentiment_value))
        
        dbExecute(con, "
          INSERT INTO sentiments(update_id, sentiment)
          VALUES($1, $2) 
          ON CONFLICT DO NOTHING
        ", params = list(p$update_id, sentiment_value))
        
        success_count <- success_count + 1
      }, error = function(e) {
        message(paste("ОШИБКА при анализе тональности:", e$message))
      })
    }
    
    message(paste("Успешно обработано", success_count, "из", nrow(pending), "сообщений"))
  } else {
    message("Нет новых сообщений для анализа тональности")
  }
  
  dbDisconnect(con)
  message("Модуль анализа тональности успешно завершен")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле sentiment.R:", e$message))
  print(traceback())
})
