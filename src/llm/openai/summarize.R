library(DBI)
library(dplyr)
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

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
")

for (i in seq_len(nrow(windows))) {
  w <- windows[i, ]
  prompt <- paste(
    "Сделай краткую сводку следующих сообщений (русский язык):",
    w$all_text,
    sep = "\n\n"
  )
  summary <- hf_complete(prompt, max_tokens = 192)
  dbExecute(con,"
    INSERT INTO summaries(chat_id, period_start, period_end, summary)
    VALUES($1,$2,$3,$4)
    ON CONFLICT(chat_id, period_start) DO UPDATE
      SET summary = EXCLUDED.summary,
          period_end = EXCLUDED.period_end
  ", params = list(w$chat_id, w$period_start, w$period_end, summary))
}

dbDisconnect(con)
