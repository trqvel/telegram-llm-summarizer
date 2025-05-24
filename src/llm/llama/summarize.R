library(DBI)
library(dplyr)
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

message("Запуск модуля summarize для создания сводок")

tryCatch({
  con <- get_db_con()

  dbExecute(con,"
    CREATE TABLE IF NOT EXISTS summaries(
      chat_id      BIGINT,
      period_start TIMESTAMP,
      period_end   TIMESTAMP,
      summary      TEXT,
      PRIMARY KEY(chat_id, period_start)
    )
  ")

  windows <- dbGetQuery(con,"
    WITH win AS (
      SELECT
        chat_id,
        date_trunc('hour', ts)
          + floor(date_part('minute', ts)/10)*interval '10 minutes'
            AS period_start,
        MAX(ts) AS period_end,
        string_agg(text_clean, E'\n') AS all_text
      FROM clean_msgs
      WHERE ts > now() - interval '10 minutes'
      GROUP BY chat_id, period_start
    )
    SELECT * FROM win
    WHERE chat_id NOT IN (
      SELECT chat_id FROM summaries 
      WHERE period_start = win.period_start
    )
  ")

  message(paste("Найдено", nrow(windows), "временных окон для суммаризации"))

  if(nrow(windows) > 0) {
    for (i in seq_len(nrow(windows))) {
      w <- windows[i, ]
      message(paste("Обработка окна", i, "из", nrow(windows), 
                   "для чата", w$chat_id))
      
      prompt <- paste(
        "Сделай краткую сводку следующих сообщений (русский язык):",
        w$all_text,
        sep = "\n\n"
      )
      
      tryCatch({
        message("Вызов Llama API для создания сводки...")
        summary <- hf_complete(prompt, max_tokens = 192)
        message("Сводка успешно создана, сохраняем в БД")
        
        dbExecute(con,"
          INSERT INTO summaries(chat_id, period_start, period_end, summary)
          VALUES($1,$2,$3,$4)
          ON CONFLICT(chat_id, period_start) DO UPDATE
            SET summary = EXCLUDED.summary,
                period_end = EXCLUDED.period_end
        ", params = list(w$chat_id, w$period_start, w$period_end, summary))
        
        message("Сводка сохранена в БД")
      }, error = function(e) {
        message(paste("ОШИБКА при создании сводки:", e$message))
      })
    }
  } else {
    message("Нет новых данных для суммаризации")
  }
  
  dbDisconnect(con)
  message("Модуль суммаризации успешно завершен")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле summarize.R:", e$message))
  print(traceback())
})
