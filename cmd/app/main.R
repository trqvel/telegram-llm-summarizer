if (file.exists(".env")) {
    readRenviron(".env")
}

library(telegram.bot)
library(parallel)

token      <- Sys.getenv("TELEGRAM_BOT_TOKEN")
bot        <- Bot(token = token)
updater    <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source("src/telegram/handlers/msg_handler.R")

etl_and_ml <- function() {
  repeat {
    source("src/db/etl/extract_data.R")
    source("src/db/etl/transform_data.R")
    source("src/db/etl/load_data.R")
    source("src/llm/openai/sentiment.R")
    source("src/llm/openai/summarize.R")
    source("src/llm/openai/gen_rss.R")
    Sys.sleep(10 * 60)
  }
}

if (requireNamespace("parallel", quietly = TRUE)) {
  parallel::mcparallel(etl_and_ml())
}

updater$start_polling()
