library(DBI)
library(dplyr)
library(openai)
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

con    <- get_db_con()
client <- get_openai()

dbExecute(con, "
  CREATE TABLE IF NOT EXISTS summaries (
    chat_id      BIGINT,
    period_start TIMESTAMP,
    period_end   TIMESTAMP,
    summary      TEXT,
    PRIMARY KEY (chat_id, period_start)
  )
")

windows <- dbGetQuery(con, "
  SELECT
    chat_id,
    date_trunc('day', ts) AS period_start,
    MAX(ts)               AS period_end,
    string_agg(text_clean, '\n') AS all_text
  FROM clean_msgs
  WHERE ts > now() - INTERVAL '1 day'
  GROUP BY chat_id, date_trunc('day', ts)
")

for (i in seq_len(nrow(windows))) {
  w <- windows[i, ]
  prompt <- paste0(
    "Сделай краткую сводку следующих сообщений (русский язык):\n\n",
    w$all_text
  )
  resp <- client$create_chat_completion(
    model    = "gpt-3.5-turbo",
    messages = list(
      list(role = "user", content = prompt)
    )
  )
  summary <- resp$choices[[1]]$message$content
  dbExecute(con, "
    INSERT INTO summaries(chat_id, period_start, period_end, summary)
    VALUES($1, $2, $3, $4)
    ON CONFLICT (chat_id, period_start) DO UPDATE
      SET summary = EXCLUDED.summary,
          period_end = EXCLUDED.period_end
  ", list(w$chat_id, w$period_start, w$period_end, summary))
}

DBI::dbDisconnect(con)
