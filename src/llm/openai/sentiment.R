library(DBI)
library(dplyr)
library(openai)

source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

con    <- get_db_con()
client <- get_openai()

dbExecute(con, "
  CREATE TABLE IF NOT EXISTS sentiments (
    update_id BIGINT PRIMARY KEY REFERENCES clean_msgs(update_id),
    sentiment TEXT
  )
")

pending <- dbGetQuery(con, "
  SELECT update_id, text_clean
  FROM clean_msgs
  WHERE update_id NOT IN (SELECT update_id FROM sentiments)
")

for (i in seq_len(nrow(pending))) {
  p     <- pending[i, ]
  prompt <- paste0(
    "Определи тональность этого сообщения: положительная, отрицательная или нейтральная.\n\n",
    p$text_clean
  )
  resp <- client$create_chat_completion(
    model    = "gpt-3.5-turbo",
    messages = list(
      list(role = "user", content = prompt)
    )
  )
  sentiment <- tolower(resp$choices[[1]]$message$content)
  dbExecute(con, "
    INSERT INTO sentiments(update_id, sentiment)
    VALUES($1, $2)
    ON CONFLICT DO NOTHING
  ", list(p$update_id, sentiment))
}

DBI::dbDisconnect(con)
