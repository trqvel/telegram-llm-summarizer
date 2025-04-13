bot_token <- "7759192678:AAHdntQNcNSoM_T1QcIzJiWAP4DgTbdcYLI"

bot <- Bot(token = bot_token)
updater <- Updater(bot = bot)
dispatcher <- updater$dispatcher
