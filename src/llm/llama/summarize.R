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
  
  message("Проверка количества сообщений в clean_msgs...")
  count_msgs <- dbGetQuery(con, "SELECT COUNT(*) as count FROM clean_msgs")
  message(paste("Всего сообщений в clean_msgs:", count_msgs$count))
  
  message("Проверка группировки сообщений по чатам...")
  chat_counts <- dbGetQuery(con, "
    SELECT chat_id, COUNT(*) as count 
    FROM clean_msgs 
    GROUP BY chat_id
  ")
  
  for(i in 1:nrow(chat_counts)) {
    message(paste("Чат ID:", chat_counts$chat_id[i], "содержит", chat_counts$count[i], "сообщений"))
  }

  message("Создание простых временных окон для суммаризации...")
  windows <- dbGetQuery(con,"
    WITH win AS (
      SELECT
        chat_id,
        date_trunc('day', ts) AS period_start,
        date_trunc('day', ts) + interval '1 day' - interval '1 second' AS period_end,
        string_agg(text_clean, E'\n') AS all_text,
        COUNT(*) as msg_count
      FROM clean_msgs
      GROUP BY chat_id, date_trunc('day', ts)
      HAVING COUNT(*) >= 2
    )
    SELECT * FROM win
    WHERE (chat_id, period_start) NOT IN (
      SELECT chat_id, period_start FROM summaries
    )
    LIMIT 10
  ")

  message(paste("Найдено", nrow(windows), "временных окон для суммаризации"))
  
  if(nrow(windows) == 0) {
    message("Диагностика: почему не найдено окон для суммаризации...")
    
    message("1. Проверка группировки по дням...")
    day_groups <- dbGetQuery(con, "
      SELECT 
        chat_id, 
        date_trunc('day', ts) AS day, 
        COUNT(*) as count
      FROM clean_msgs
      GROUP BY chat_id, date_trunc('day', ts)
    ")
    
    if(nrow(day_groups) == 0) {
      message("ОШИБКА: Нет данных для группировки по дням")
    } else {
      message(paste("Найдено", nrow(day_groups), "групп по дням"))
      for(i in 1:min(nrow(day_groups), 5)) {
        message(paste("  Чат:", day_groups$chat_id[i], "День:", day_groups$day[i], "Сообщений:", day_groups$count[i]))
      }
      
      message("2. Проверка минимального количества сообщений...")
      valid_groups <- dbGetQuery(con, "
        SELECT 
          chat_id, 
          date_trunc('day', ts) AS day, 
          COUNT(*) as count
        FROM clean_msgs
        GROUP BY chat_id, date_trunc('day', ts)
        HAVING COUNT(*) >= 2
      ")
      
      if(nrow(valid_groups) == 0) {
        message("ОШИБКА: Нет групп с 2 и более сообщениями")
      } else {
        message(paste("Найдено", nrow(valid_groups), "групп с 2+ сообщениями"))
        
        message("3. Проверка существующих сводок...")
        existing_summaries <- dbGetQuery(con, "SELECT COUNT(*) as count FROM summaries")
        message(paste("Существующих сводок:", existing_summaries$count))
        
        if(existing_summaries$count > 0) {
          message("4. Проверка пересечения с существующими сводками...")
          intersect_check <- dbGetQuery(con, "
            WITH valid_groups AS (
              SELECT 
                chat_id, 
                date_trunc('day', ts) AS period_start
              FROM clean_msgs
              GROUP BY chat_id, date_trunc('day', ts)
              HAVING COUNT(*) >= 2
            )
            SELECT COUNT(*) as count
            FROM valid_groups v
            WHERE (v.chat_id, v.period_start) IN (
              SELECT chat_id, period_start FROM summaries
            )
          ")
          message(paste("Пересечений с существующими сводками:", intersect_check$count))
        }
      }
    }
    
    message("Попытка создать хотя бы одну сводку, игнорируя существующие...")
    force_windows <- dbGetQuery(con,"
      WITH win AS (
        SELECT
          chat_id,
          date_trunc('day', ts) AS period_start,
          date_trunc('day', ts) + interval '1 day' - interval '1 second' AS period_end,
          string_agg(text_clean, E'\n') AS all_text,
          COUNT(*) as msg_count
        FROM clean_msgs
        GROUP BY chat_id, date_trunc('day', ts)
        HAVING COUNT(*) >= 2
        LIMIT 1
      )
      SELECT * FROM win
    ")
    
    if(nrow(force_windows) > 0) {
      message("Найдено принудительное окно для суммаризации!")
      windows <- force_windows
    }
  }

  if(nrow(windows) > 0) {
    for (i in seq_len(nrow(windows))) {
      w <- windows[i, ]
      message(paste("Обработка окна", i, "из", nrow(windows), 
                   "для чата", w$chat_id, "с", w$msg_count, "сообщениями"))
      
      prompt <- paste(
        "Сделай краткую сводку следующих сообщений (русский язык):",
        w$all_text,
        sep = "\n\n"
      )
      
      tryCatch({
        message("Вызов Llama API для создания сводки...")
        summary <- hf_complete(prompt, max_tokens = 192)
        message("Сводка успешно создана, сохраняем в БД")
        
        summary <- enc2utf8(summary)
        message(paste("Текст сводки:", summary))
        
        dbExecute(con,"
          INSERT INTO summaries(chat_id, period_start, period_end, summary)
          VALUES($1,$2,$3,$4)
          ON CONFLICT(chat_id, period_start) DO UPDATE
            SET summary = EXCLUDED.summary,
                period_end = EXCLUDED.period_end
        ", params = list(w$chat_id, w$period_start, w$period_end, summary))
        
        message("Сводка сохранена в БД")
        
        # Проверка успешности вставки
        check <- dbGetQuery(con, "
          SELECT COUNT(*) as count FROM summaries 
          WHERE chat_id = $1 AND period_start = $2
        ", params = list(w$chat_id, w$period_start))
        
        if(check$count > 0) {
          message("Запись успешно добавлена в таблицу summaries")
        } else {
          message("ОШИБКА: Запись не была добавлена в таблицу summaries!")
        }
      }, error = function(e) {
        message(paste("ОШИБКА при создании сводки:", e$message))
        print(traceback())
      })
    }
  } else {
    message("Нет новых данных для суммаризации")
  }
  
  final_count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM summaries")
  message(paste("Итоговое количество сводок в БД:", final_count$count))
  
  dbDisconnect(con)
  message("Модуль суммаризации успешно завершен")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле summarize.R:", e$message))
  print(traceback())
})
