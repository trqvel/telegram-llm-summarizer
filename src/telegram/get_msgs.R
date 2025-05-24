if (file.exists(".env")) readRenviron(".env")

library(telegram.bot)
library(jsonlite)
library(DBI)
library(RPostgres)

source("src/db/connection_db.R")

token <- Sys.getenv("TELEGRAM_BOT_TOKEN")
message(paste("Токен бота (частично скрыт):", ifelse(nchar(token) > 10, 
               paste0(substr(token, 1, 4), "...", substr(token, nchar(token)-3, nchar(token))), 
               "не найден или слишком короткий")))

bot <- tryCatch({
  Bot(token = token)
}, error = function(e) {
  message(paste("ОШИБКА при создании объекта бота:", e$message))
  stop("Невозможно создать объект бота. Проверьте токен.")
})

message("Проверяем подключение к API")
me <- tryCatch({
  bot$getMe()
}, error = function(e) {
  message(paste("ОШИБКА при вызове getMe():", e$message))
  stop("Невозможно подключиться к API Telegram. Проверьте токен и подключение.")
})
message(paste("Бот идентифицирован:", me$username))

message("Удаляем webhook для использования long polling")
tryCatch({
  bot$deleteWebhook()
  message("Webhook успешно удален")
}, error = function(e) {
  message(paste("ОШИБКА при удалении webhook:", e$message))
  message("Продолжаем выполнение, возможно webhook не был установлен")
})

message("Запрашиваем последние сообщения")
updates <- tryCatch({
  bot$getUpdates(limit = 10, timeout = 10)
}, error = function(e) {
  message(paste("ОШИБКА при получении обновлений:", e$message))
  list()
})

message(paste("Получено обновлений:", length(updates)))

con <- tryCatch({
  get_db_con()
}, error = function(e) {
  message(paste("ОШИБКА при подключении к БД:", e$message))
  stop("Невозможно подключиться к базе данных. Проверьте настройки подключения.")
})

message("Проверка структуры таблицы raw_msgs")
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
  has_processed_column <- TRUE
} else {
  message("Проверяем наличие столбца processed в таблице raw_msgs")
  cols <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'raw_msgs'")
  has_processed_column <- "processed" %in% cols$column_name
  message(paste("Столбец processed", ifelse(has_processed_column, "существует", "отсутствует"), "в таблице"))
  
  if (!has_processed_column) {
    message("Добавляем столбец processed в таблицу raw_msgs")
    tryCatch({
      dbExecute(con, "ALTER TABLE raw_msgs ADD COLUMN processed BOOLEAN DEFAULT FALSE")
      has_processed_column <- TRUE
      message("Столбец processed успешно добавлен")
    }, error = function(e) {
      message(paste("ОШИБКА при добавлении столбца processed:", e$message))
    })
  }
}

for (update in updates) {
  message(paste("Обновление ID:", update$update_id))
  
  if (!is.null(update$message)) {
    if (!is.null(update$message$text)) {
      message(paste("Текст:", update$message$text))
    }
    message(paste("Чат ID:", update$message$chat$id))
    if (!is.null(update$message$from$username)) {
      message(paste("От:", update$message$from$username))
    } else {
      message(paste("От ID:", update$message$from$id))
    }
  }
  
  update_data <- list(
    update_id = update$update_id,
    message = list(
      message_id = update$message$message_id,
      date = update$message$date,
      text = update$message$text,
      chat = list(
        id = update$message$chat$id,
        type = update$message$chat$type,
        title = update$message$chat$title
      ),
      from = list(
        id = update$message$from$id,
        is_bot = update$message$from$is_bot,
        first_name = update$message$from$first_name,
        username = update$message$from$username
      )
    )
  )
  
  update_json <- tryCatch({
    toJSON(update_data, auto_unbox = TRUE)
  }, error = function(e) {
    message(paste("ОШИБКА при преобразовании в JSON:", e$message))
    "{}"
  })
  
  if (update_json != "{}") {
    sql <- ifelse(has_processed_column,
      "INSERT INTO raw_msgs (update_id, update_json, processed) VALUES ($1, $2, FALSE) ON CONFLICT (update_id) DO NOTHING",
      "INSERT INTO raw_msgs (update_id, update_json) VALUES ($1, $2) ON CONFLICT (update_id) DO NOTHING"
    )
    
    result <- tryCatch({
      dbExecute(con, sql, params = list(update$update_id, update_json))
    }, error = function(e) {
      message(paste("ОШИБКА при вставке в БД:", e$message))
      0
    })
    
    message(paste("Вставлено строк:", result))
  } else {
    message("Пропуск записи из-за ошибки JSON")
  }
}

message("Проверяем, что сообщения попали в БД")
count <- dbGetQuery(con, "SELECT COUNT(*) FROM raw_msgs")
message(paste("Всего записей в raw_msgs:", count[[1]]))

latest <- dbGetQuery(con, "SELECT update_id, ts_insert FROM raw_msgs ORDER BY update_id DESC LIMIT 5")
message("Последние записи:")
print(latest)

dbDisconnect(con)

message("Проверка завершена") 