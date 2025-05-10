if (file.exists(".env")) {
    readRenviron(".env")
}

library(telegram.bot)
library(parallel)
library(openai)

token      <- Sys.getenv("TELEGRAM_BOT_TOKEN")
bot        <- Bot(token = token)
updater    <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source("src/telegram/handlers/msg_handler.R")
source("src/db/connection_db.R")
source("src/llm/connection_ai.R")

etl_scheduler <- function() {
  while (TRUE) {
    source("src/etl/extract_data.R")
    source("src/etl/transform_data.R")
    source("src/etl/load_data.R")
    Sys.sleep(10 * 60)
  }
}

if (requireNamespace("parallel", quietly = TRUE)) {
  parallel::mcparallel(etl_scheduler())
}

updater$start_polling()
