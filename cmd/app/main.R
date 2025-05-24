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

future({
  repeat {
    tryCatch({
      message("--- Начало ETL-процесса ---")
      
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
      
      message("--- ETL-процесс успешно завершен ---")
    }, error = function(e) {
      message(paste("!!! ОШИБКА в ETL-процессе:", e$message))
      print(traceback())
    })
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
