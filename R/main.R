library(telegram.bot)


setwd(dirname(rstudioapi::getActiveDocumentContext()$path))

source("telegram/init.R")
source("telegram/handlers/read_msg.R")
source("telegram/handlers/group_monitor.R")

updater$start_polling()
