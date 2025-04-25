if (file.exists(".env")) {
  readRenviron(".env")
}

library(telegram.bot)

token   <- Sys.getenv("TELEGRAM_BOT_TOKEN")
bot     <- Bot(token = token)
updater <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source("src/telegram/handlers/msg_handler.R")

etl_scheduler <- function() {
  while (TRUE) {
    source("src/db/etl/extract_data.R")
    source("src/db/etl/transform_data.R")
    source("src/db/etl/load_data.R")
    Sys.sleep(10 * 60)
  }
}

if (requireNamespace("parallel", quietly = TRUE)) {
  parallel::mcparallel(etl_scheduler())
}

updater$start_polling()
