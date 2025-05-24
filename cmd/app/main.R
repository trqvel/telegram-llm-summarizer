if (file.exists(".env")) readRenviron(".env")

need <- c(
  "telegram.bot", "future", "parallelly", "DBI", "RPostgres",
  "dplyr", "stringr", "stringi", "lubridate", "jsonlite",
  "huggingfaceR", "xml2", "shiny", "shinydashboard", "sodium", "DT",
  "openssl"
)
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) install.packages(miss, repos = "https://cloud.r-project.org")

library(telegram.bot)
library(future)

find_root_dir <- function() {
  current <- getwd()
  
  if (basename(current) == "app" && basename(dirname(current)) == "cmd") {
    return(dirname(dirname(current)))
  }
  
  if (basename(current) == "cmd") {
    return(dirname(current))
  }
  
  if (dir.exists(file.path(current, "src")) && dir.exists(file.path(current, "cmd"))) {
    return(current)
  }
  
  parent <- normalizePath(file.path(current, ".."))
  if (dir.exists(file.path(parent, "src")) && dir.exists(file.path(parent, "cmd"))) {
    return(parent)
  }
  
  return(current)
}

root_dir <- find_root_dir()
message("Используется корневая директория: ", root_dir)
setwd(root_dir)

if (identical(Sys.getenv("HF_API_TOKEN"), "")) {
  stop("HF_API_TOKEN не установлен в .env файле")
}

tryCatch({
  source(file.path(root_dir, "src/db/connection_db.R"))
  con <- get_db_con()
  dbDisconnect(con)
  message("Подключение к БД успешно проверено")
}, error = function(e) {
  stop(paste("Ошибка подключения к БД:", e$message))
})

token <- Sys.getenv("TELEGRAM_BOT_TOKEN")
if (identical(token, "")) {
  stop("TELEGRAM_BOT_TOKEN не установлен в .env файле")
}

bot <- Bot(token = token)

tryCatch({
  bot$deleteWebhook()
  message("Webhook удален, используем режим polling")
}, error = function(e) {
  warning(paste("Ошибка при удалении webhook:", e$message))
})

updater <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source(file.path(root_dir, "src/telegram/handlers/msg_handler.R"))

plan(multisession)

generate_test_data <- function() {
  message("Генерация тестовых данных для заполнения БД...")
  
  tryCatch({
    con <- get_db_con()
    
    stat <- dbGetQuery(con, "
      SELECT 
        (SELECT COUNT(*) FROM raw_msgs) as raw_count,
        (SELECT COUNT(*) FROM clean_msgs) as clean_count,
        (SELECT COUNT(*) FROM sentiments) as sent_count,
        (SELECT COUNT(*) FROM summaries) as summ_count
    ")
    
    message(paste("Текущая статистика БД: raw_msgs:", stat$raw_count, 
                 "clean_msgs:", stat$clean_count, 
                 "sentiments:", stat$sent_count, 
                 "summaries:", stat$summ_count))
    
    if (stat$raw_count < 10) {
      message("Генерация тестовых сообщений...")
      
      chat_ids <- c(-1001234567890, -1002345678901, -1003456789012)
      chat_titles <- c("Тестовая группа 1", "Разработка проекта", "Маркетинг и продажи")
      
      user_ids <- c(123456781, 123456782, 123456783, 123456784, 123456785)
      user_names <- c("ivan_test", "maria_test", "alex_test", "elena_test", "sergey_test")
      user_first_names <- c("Иван", "Мария", "Александр", "Елена", "Сергей")
      
      texts <- c(
        "Привет всем! Как дела у всех сегодня?",
        "Давайте обсудим последние новости в индустрии.",
        "Кто-нибудь может помочь с проблемой в коде?",
        "Отличная работа команды на этой неделе!",
        "Предлагаю встретиться на следующей неделе для обсуждения.",
        "Спасибо всем за участие в дискуссии.",
        "Новые требования к проекту были отправлены по почте.",
        "Поздравляю с успешным запуском!",
        "Не забудьте про дедлайн на следующей неделе.",
        "Какие у всех планы на выходные?",
        "Сегодня у нас отличные новости - проект одобрен!",
        "Нужно срочно исправить баг в production.",
        "Кто может помочь с тестированием нового функционала?",
        "Отчет по проекту готов, посмотрите пожалуйста.",
        "В следующем релизе мы добавим новую фичу."
      )
      
      message("Добавление тестовых сообщений в raw_msgs...")
      
      for (day_offset in 0:6) {
        for (hour_offset in 0:3) {
          for (chat_index in 1:length(chat_ids)) {
            chat_id <- chat_ids[chat_index]
            chat_title <- chat_titles[chat_index]
            
            date <- Sys.time() - (day_offset * 86400) - (hour_offset * 3600)
            
            user_index <- sample(1:length(user_ids), 1)
            user_id <- user_ids[user_index]
            username <- user_names[user_index]
            first_name <- user_first_names[user_index]
            
            text <- texts[sample(1:length(texts), 1)]
            
            update_id <- as.integer(as.numeric(date) * 1000) + 
                          day_offset * 1000 + 
                          hour_offset * 100 + 
                          chat_index
            
            update_data <- list(
              update_id = update_id,
              message = list(
                message_id = day_offset * 100 + hour_offset * 10 + chat_index,
                date = as.integer(as.numeric(date)),
                text = text,
                chat = list(
                  id = chat_id,
                  type = "supergroup",
                  title = chat_title
                ),
                from = list(
                  id = user_id,
                  is_bot = FALSE,
                  first_name = first_name,
                  username = username
                )
              )
            )
            
            update_json <- toJSON(update_data, auto_unbox = TRUE)
            
            tryCatch({
              dbExecute(con, "
                INSERT INTO raw_msgs(update_id, update_json, processed)
                VALUES($1, $2, FALSE)
                ON CONFLICT (update_id) DO NOTHING
              ", params = list(update_id, update_json))
              message(paste("Тестовое сообщение с ID", update_id, "добавлено в raw_msgs"))
            }, error = function(e) {
              message(paste("ОШИБКА при добавлении тестового сообщения в raw_msgs:", e$message))
            })
            
            tryCatch({
              text_clean <- gsub("https?://\\S+", "", text)
              text_clean <- gsub("<[^>]+>", "", text_clean)
              
              dbExecute(con, "
                INSERT INTO clean_msgs(update_id, chat_id, chat_title, user_id, user_name, ts, text_clean)
                VALUES($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (update_id) DO NOTHING
              ", params = list(
                update_id, 
                chat_id, 
                chat_title,
                user_id,
                username,
                as.POSIXct(date),
                text_clean
              ))
              message(paste("Сообщение с ID", update_id, "добавлено в clean_msgs"))
            }, error = function(e) {
              message(paste("ОШИБКА при добавлении сообщения в clean_msgs:", e$message))
            })
            
            tryCatch({
              sentiment_values <- c("положительная", "нейтральная", "отрицательная")
              sentiment <- sentiment_values[sample(1:3, 1)]
              
              dbExecute(con, "
                INSERT INTO sentiments(update_id, sentiment)
                VALUES($1, $2)
                ON CONFLICT (update_id) DO NOTHING
              ", params = list(update_id, sentiment))
              message(paste("Тональность для сообщения", update_id, "добавлена:", sentiment))
            }, error = function(e) {
              message(paste("ОШИБКА при добавлении тональности:", e$message))
            })
          }
        }
      }
      
      message("Генерация тестовых сводок...")
      
      for (day_offset in 0:6) {
        for (chat_index in 1:length(chat_ids)) {
          chat_id <- chat_ids[chat_index]
          
          period_start <- as.POSIXct(Sys.Date() - day_offset)
          period_end <- period_start + 86400 - 1
          
          summaries <- c(
            "Участники обсуждали текущие задачи проекта и планировали следующий этап разработки.",
            "Обсуждались вопросы маркетинга и продвижения продукта на рынке.",
            "Техническая дискуссия о решении проблем с производительностью системы.",
            "Планирование встречи и распределение задач между участниками команды.",
            "Обсуждение результатов тестирования и выявленных багов в системе."
          )
          
          summary <- summaries[sample(1:length(summaries), 1)]
          
          tryCatch({
            dbExecute(con, "
              INSERT INTO summaries(chat_id, period_start, period_end, summary)
              VALUES($1, $2, $3, $4)
              ON CONFLICT (chat_id, period_start) DO UPDATE
                SET summary = EXCLUDED.summary,
                    period_end = EXCLUDED.period_end
            ", params = list(chat_id, period_start, period_end, summary))
            message(paste("Сводка для чата", chat_id, "на дату", period_start, "добавлена"))
          }, error = function(e) {
            message(paste("ОШИБКА при добавлении сводки:", e$message))
          })
        }
      }
      
      stat_after <- dbGetQuery(con, "
        SELECT 
          (SELECT COUNT(*) FROM raw_msgs) as raw_count,
          (SELECT COUNT(*) FROM clean_msgs) as clean_count,
          (SELECT COUNT(*) FROM sentiments) as sent_count,
          (SELECT COUNT(*) FROM summaries) as summ_count
      ")
      
      message(paste("Статистика после генерации: raw_msgs:", stat_after$raw_count, 
                   "clean_msgs:", stat_after$clean_count, 
                   "sentiments:", stat_after$sent_count, 
                   "summaries:", stat_after$summ_count))
      
      message("Генерация тестовых данных завершена")
    } else {
      message("Достаточно существующих данных, пропускаем генерацию тестовых")
    }
    
    dbDisconnect(con)
  }, error = function(e) {
    message(paste("КРИТИЧЕСКАЯ ОШИБКА при генерации тестовых данных:", e$message))
    print(traceback())
  })
}

generate_test_data()

run_etl_cycle <- function() {
  message("--- Начало полного ETL-цикла ---")
  
  message("Проверка статистики БД перед ETL-циклом...")
  con <- get_db_con()
  stat_before <- dbGetQuery(con, "
    SELECT 
      (SELECT COUNT(*) FROM raw_msgs) as raw_count,
      (SELECT COUNT(*) FROM clean_msgs) as clean_count,
      (SELECT COUNT(*) FROM sentiments) as sent_count,
      (SELECT COUNT(*) FROM summaries) as summ_count
  ")
  dbDisconnect(con)
  
  message(paste("ПЕРЕД ETL: raw_msgs:", stat_before$raw_count, 
               "clean_msgs:", stat_before$clean_count, 
               "sentiments:", stat_before$sent_count, 
               "summaries:", stat_before$summ_count))
  
  tryCatch({
    message("Запуск extract_data.R...")
    source(file.path(root_dir, "src/db/etl/extract_data.R"))
    
    message("Запуск transform_data.R...")
    source(file.path(root_dir, "src/db/etl/transform_data.R"))
    
    message("Запуск load_data.R...")
    source(file.path(root_dir, "src/db/etl/load_data.R"))
    
    message("Запуск sentiment.R...")
    source(file.path(root_dir, "src/llm/llama/sentiment.R"))
    
    message("Запуск summarize.R...")
    source(file.path(root_dir, "src/llm/llama/summarize.R"))
    
    message("Запуск gen_rss.R...")
    source(file.path(root_dir, "src/llm/llama/gen_rss.R"))
    
    message("Проверка статистики БД после ETL-цикла...")
    con <- get_db_con()
    stat_after <- dbGetQuery(con, "
      SELECT 
        (SELECT COUNT(*) FROM raw_msgs) as raw_count,
        (SELECT COUNT(*) FROM clean_msgs) as clean_count,
        (SELECT COUNT(*) FROM sentiments) as sent_count,
        (SELECT COUNT(*) FROM summaries) as summ_count
    ")
    dbDisconnect(con)
    
    message(paste("ПОСЛЕ ETL: raw_msgs:", stat_after$raw_count, 
                 "clean_msgs:", stat_after$clean_count, 
                 "sentiments:", stat_after$sent_count, 
                 "summaries:", stat_after$summ_count))
    
    changes <- data.frame(
      raw_diff = stat_after$raw_count - stat_before$raw_count,
      clean_diff = stat_after$clean_count - stat_before$clean_count,
      sent_diff = stat_after$sent_count - stat_before$sent_count,
      summ_diff = stat_after$summ_count - stat_before$summ_count
    )
    
    message(paste("ИЗМЕНЕНИЯ: raw_msgs:", changes$raw_diff, 
                 "clean_msgs:", changes$clean_diff, 
                 "sentiments:", changes$sent_diff, 
                 "summaries:", changes$summ_diff))
    
  }, error = function(e) {
    message(paste("!!! ОШИБКА в ETL-процессе:", e$message))
    print(traceback())
  })
  
  message("--- ETL-цикл завершен ---")
}

run_etl_cycle()

future({
  repeat {
    tryCatch({
      run_etl_cycle()
    }, error = function(e) {
      message(paste("!!! КРИТИЧЕСКАЯ ОШИБКА при запуске ETL-цикла:", e$message))
      print(traceback())
    })
    message(paste("Следующий ETL-цикл запланирован через", 600, "секунд"))
    Sys.sleep(600)
  }
}, seed = FALSE)

future({
  repeat {
    tryCatch({
      message("Запрашиваем обновления от Telegram API...")
      updates <- bot$getUpdates(timeout = 30)
      
      if (length(updates) > 0) {
        message(paste("Получено обновлений:", length(updates)))
        for (update in updates) {
          tryCatch({
            message(paste("Обработка update_id:", update$update_id))
            msg_handler(bot, update)
            
            bot$getUpdates(offset = update$update_id + 1, limit = 1, timeout = 0)
          }, error = function(e) {
            message(paste("Ошибка при обработке update_id", update$update_id, ":", e$message))
          })
        }
      } else {
        message("Нет новых обновлений")
      }
    }, error = function(e) {
      message(paste("Ошибка при получении обновлений:", e$message))
    })
    Sys.sleep(5)
  }
}, seed = FALSE)

appDir <- file.path(root_dir, "src/app")
message("Запуск Shiny по адресу: http://127.0.0.1:3838")
options(shiny.autoreload = TRUE)
shiny::runApp(appDir, host = "127.0.0.1", port = 3838)
