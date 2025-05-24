library(DBI)
library(dplyr)
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

con <- get_db_con()

dbExecute(con,"
  CREATE TABLE IF NOT EXISTS sentiments(
    update_id BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
    sentiment TEXT
  )
")

pending <- dbGetQuery(con,"
  SELECT update_id, text_clean
  FROM clean_msgs
  WHERE update_id NOT IN (SELECT update_id FROM sentiments)
")

for (i in seq_len(nrow(pending))) {
  p <- pending[i, ]
  prompt <- paste(
    "Определи тональность этого сообщения:",
    "положительная, отрицательная или нейтральная.",
    p$text_clean,
    sep = "\n\n"
  )
  sentiment <- tolower(hf_complete(prompt, max_tokens = 16))
  dbExecute(con,"
    INSERT INTO sentiments(update_id, sentiment)
    VALUES($1,$2) ON CONFLICT DO NOTHING
  ", params = list(p$update_id, sentiment))
}

dbDisconnect(con)
