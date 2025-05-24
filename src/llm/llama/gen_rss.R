library(DBI)
library(xml2)
source("src/db/connection_db.R")

message("Запуск модуля генерации RSS-ленты")

tryCatch({
  con <- get_db_con()
  
  summaries <- dbGetQuery(con, "
    SELECT chat_id, period_start, summary
    FROM summaries
    WHERE period_start > NOW() - INTERVAL '7 days'
    ORDER BY period_start DESC
    LIMIT 50
  ")
  
  message(paste("Получено", nrow(summaries), "сводок для RSS"))
  
  if (nrow(summaries) > 0) {
    for (i in 1:nrow(summaries)) {
      Encoding(summaries$summary[i]) <- "UTF-8"
    }
    
    tryCatch({
      rss <- xml_new_document() %>%
        xml_add_child("rss", version = "2.0") %>%
        xml_add_child("channel")
      
      rss %>%
        xml_add_child("title", "Telegram LLM Summaries RSS") %>%
        xml_add_child("link", "https://tlgrm.ru") %>%
        xml_add_child("description", "Последние краткие сводки сообщений из Telegram-групп")
      
      for (i in 1:nrow(summaries)) {
        s <- summaries[i, ]
        
        group_info <- dbGetQuery(con, "
          SELECT DISTINCT chat_title 
          FROM clean_msgs 
          WHERE chat_id = $1
          LIMIT 1
        ", params = list(s$chat_id))
        
        if (nrow(group_info) > 0 && !is.na(group_info$chat_title[1])) {
          Encoding(group_info$chat_title[1]) <- "UTF-8"
          chat_title <- group_info$chat_title[1]
        } else {
          chat_title <- paste("Группа", s$chat_id)
        }
        
        item_title <- paste0(chat_title, " - ", format(s$period_start, "%Y-%m-%d %H:%M"))
        
        tryCatch({
          item <- rss %>%
            xml_add_child("item") %>%
            xml_add_child("title", item_title) %>%
            xml_parent() %>%
            xml_add_child("description", s$summary) %>%
            xml_parent() %>%
            xml_add_child("pubDate", format(s$period_start, "%a, %d %b %Y %H:%M:%S %z")) %>%
            xml_parent() %>%
            xml_add_child("guid", paste0("tg-llm-", s$chat_id, "-", format(s$period_start, "%Y%m%d%H%M%S")))
          
          message(paste("Добавлен элемент RSS для группы", chat_title))
        }, error = function(e) {
          message(paste("ОШИБКА при добавлении элемента RSS:", e$message))
        })
      }
      
      public_dir <- file.path(getwd(), "public")
      if (!dir.exists(public_dir)) {
        dir.create(public_dir, recursive = TRUE)
        message(paste("Создана директория:", public_dir))
      }
      
      rss_file <- file.path(public_dir, "feed.xml")
      xml_save(xml_root(rss), rss_file, encoding = "UTF-8")
      message(paste("RSS-лента успешно сохранена в", rss_file))
      
      html_content <- paste0(
        "<!DOCTYPE html>
        <html>
        <head>
          <meta charset='UTF-8'>
          <title>Telegram LLM Summaries</title>
          <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            h1 { color: #0088cc; }
            .item { border-bottom: 1px solid #eee; padding: 10px 0; }
            .title { font-weight: bold; }
            .summary { margin: 10px 0; }
            .date { color: #888; font-size: 0.9em; }
          </style>
        </head>
        <body>
          <h1>Telegram LLM Summaries</h1>
          <div id='items'>")
      
      for (i in 1:nrow(summaries)) {
        s <- summaries[i, ]
        
        group_info <- dbGetQuery(con, "
          SELECT DISTINCT chat_title 
          FROM clean_msgs 
          WHERE chat_id = $1
          LIMIT 1
        ", params = list(s$chat_id))
        
        if (nrow(group_info) > 0 && !is.na(group_info$chat_title[1])) {
          Encoding(group_info$chat_title[1]) <- "UTF-8"
          chat_title <- group_info$chat_title[1]
        } else {
          chat_title <- paste("Группа", s$chat_id)
        }
        
        item_title <- paste0(chat_title, " - ", format(s$period_start, "%Y-%m-%d %H:%M"))
        
        html_content <- paste0(
          html_content,
          "<div class='item'>",
          "<div class='title'>", item_title, "</div>",
          "<div class='summary'>", s$summary, "</div>",
          "<div class='date'>", format(s$period_start, "%a, %d %b %Y %H:%M:%S"), "</div>",
          "</div>"
        )
      }
      
      html_content <- paste0(
        html_content,
        "          </div>
        </body>
        </html>")
      
      html_file <- file.path(public_dir, "index.html")
      writeLines(html_content, html_file, useBytes = TRUE)
      message(paste("HTML-страница успешно сохранена в", html_file))
      
    }, error = function(e) {
      message(paste("ОШИБКА при создании RSS:", e$message))
    })
  } else {
    message("Нет данных для генерации RSS")
  }
  
  dbDisconnect(con)
  message("Модуль генерации RSS успешно завершен")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле gen_rss.R:", e$message))
  print(traceback())
})
