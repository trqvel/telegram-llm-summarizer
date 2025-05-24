library(DBI)
library(xml2)
source("src/db/connection_db.R")

message("Запуск модуля генерации RSS-ленты")

tryCatch({
  con <- get_db_con()
  
  summaries <- dbGetQuery(con, "
    SELECT chat_id, period_start, summary
    FROM summaries
    WHERE period_start > NOW() - INTERVAL '24 hours'
    ORDER BY period_start DESC
    LIMIT 20
  ")
  
  message(paste("Получено", nrow(summaries), "сводок для RSS"))
  
  if (nrow(summaries) > 0) {
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
      
      chat_title <- if (nrow(group_info) > 0 && !is.na(group_info$chat_title[1])) {
        group_info$chat_title[1]
      } else {
        paste("Группа", s$chat_id)
      }
      
      item_title <- paste0(chat_title, " - ", format(s$period_start, "%Y-%m-%d %H:%M"))
      
      item <- rss %>%
        xml_add_child("item") %>%
        xml_add_child("title", item_title) %>%
        xml_parent() %>%
        xml_add_child("description", s$summary) %>%
        xml_parent() %>%
        xml_add_child("pubDate", format(s$period_start, "%a, %d %b %Y %H:%M:%S %z")) %>%
        xml_parent() %>%
        xml_add_child("guid", paste0("tg-llm-", s$chat_id, "-", format(s$period_start, "%Y%m%d%H%M%S")))
    }
    
    rss_file <- file.path(getwd(), "public/feed.xml")
    dir.create(dirname(rss_file), showWarnings = FALSE, recursive = TRUE)
    
    xml_save(xml_root(rss), rss_file)
    message(paste("RSS-лента успешно сохранена в", rss_file))
  } else {
    message("Нет данных для генерации RSS")
  }
  
  dbDisconnect(con)
  message("Модуль генерации RSS успешно завершен")
}, error = function(e) {
  message(paste("КРИТИЧЕСКАЯ ОШИБКА в модуле gen_rss.R:", e$message))
  print(traceback())
})
