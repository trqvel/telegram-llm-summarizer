if (file.exists(".env")) readRenviron(".env")

need <- c(
  "telegram.bot", "future", "parallelly", "DBI", "RPostgres",
  "dplyr", "stringr", "stringi", "lubridate", "jsonlite",
  "openai", "xml2", "shiny", "shinydashboard", "sodium", "DT"
)
miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) install.packages(miss, repos = "https://cloud.r-project.org")

library(telegram.bot)
library(future)

script_path <- normalizePath(sys.frame(1)$ofile)
root_dir <- dirname(dirname(dirname(script_path)))
setwd(root_dir)

token      <- Sys.getenv("TELEGRAM_BOT_TOKEN")
bot        <- Bot(token = token)
updater    <- Updater(bot = bot)
dispatcher <- updater$dispatcher

source(file.path(root_dir, "src/telegram/handlers/msg_handler.R"))

plan(multisession)

future({
  repeat {
    source(file.path(root_dir, "src/db/etl/extract_data.R"))
    source(file.path(root_dir, "src/db/etl/transform_data.R"))
    source(file.path(root_dir, "src/db/etl/load_data.R"))
    source(file.path(root_dir, "src/llm/openai/sentiment.R"))
    source(file.path(root_dir, "src/llm/openai/summarize.R"))
    source(file.path(root_dir, "src/llm/openai/gen_rss.R"))
    Sys.sleep(600)
  }
}, seed = FALSE)

future({
  updater$start_polling()
}, seed = FALSE)

appDir <- file.path(root_dir, "src/app")
message("Запуск Shiny по адресу: http://localhost:3838")
options(shiny.autoreload = TRUE)
shiny::runApp(appDir, host = "0.0.0.0", port = 3838)
