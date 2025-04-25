if (file.exists(".env")) {
  readRenviron(".env")
}

library(telegram.bot)

token   <- Sys.getenv("TELEGRAM_BOT_TOKEN")
bot     <- Bot(token = token)
updater <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source("src/telegram/handlers/msg_handler.R")

updater$start_polling()
