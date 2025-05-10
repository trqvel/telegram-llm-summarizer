library(DBI)
library(RPostgres)
library(dplyr)
library(xml2)

source("src/db/connection_db.R")

con <- get_db_con()

summaries <- dbGetQuery(con, "
    SELECT chat_id, period_start, summary
    FROM summaries
    ORDER BY period_start DESC
    LIMIT 20
")

feed <- xml_new_root("rss")
xml_set_attr(feed, "version", "2.0")

channel <- xml_add_child(feed, "channel")
xml_add_child(channel, "title",       "Telegram LLM Summaries RSS")
xml_add_child(channel, "link",        "")
xml_add_child(channel, "description", "Последние краткие сводки сообщений из Telegram-групп")

for (i in seq_len(nrow(summaries))) {
    item <- xml_add_child(channel, "item")

    xml_add_child(
        item, "title",
        sprintf("Группа %s — %s",
                summaries$chat_id[i],
                summaries$period_start[i])
    )
    xml_add_child(item, "link",        "")
    xml_add_child(
        item, "guid",
        paste0(summaries$chat_id[i], "_", summaries$period_start[i])
    )
    xml_add_child(
        item, "pubDate",
        format(summaries$period_start[i],
               "%a, %d %b %Y %H:%M:%S +0000")
    )
    xml_add_child(item, "description", summaries$summary[i])
}

dir.create("public", showWarnings = FALSE)
write_xml(feed, "public/feed.xml")

DBI::dbDisconnect(con)
