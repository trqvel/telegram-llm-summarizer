library(shiny)
library(DBI)
library(RPostgres)
library(sodium)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

login_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h2("Вход"),
    textInput(ns("login"),  "Логин"),
    passwordInput(ns("pwd"), "Пароль"),
    actionButton(ns("go"), "Войти"),
    br(), verbatimTextOutput(ns("msg"))
  )
}

login_server <- function(id, user) {
  moduleServer(id, function(input, output, session) {

    output$msg <- renderText({ rv$msg })
    rv <- reactiveValues(msg = NULL)

    observeEvent(input$go, {
      con  <- get_db_con()
      info <- dbGetQuery(con,
        "SELECT id, username, password_hash FROM users WHERE username = $1",
        params = list(input$login)
      )
      dbDisconnect(con)

      if (nrow(info) == 1) {
        valid <- sodium::password_verify(
          sodium::hex2bin(info$password_hash[1]),
          charToRaw(input$pwd)
        )
        if (isTRUE(valid)) {
          user(list(id = info$id[1], name = info$username[1]))
          rv$msg <- NULL
          return()
        }
      }
      rv$msg <- "Неверный логин или пароль."
    })
  })
}
