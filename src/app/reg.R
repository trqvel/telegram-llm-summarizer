library(shiny)
library(DBI)
library(RPostgres)
library(sodium)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

register_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h2("Регистрация"),
    textInput(ns("login"),  "Логин"),
    passwordInput(ns("pwd"),  "Пароль"),
    passwordInput(ns("pwd2"), "Повтор пароля"),
    actionButton(ns("submit"), "Создать аккаунт"),
    br(), verbatimTextOutput(ns("msg"))
  )
}

register_server <- function(id) {
  moduleServer(id, function(input, output, session) {

    output$msg <- renderText({
      req(rv$msg)
      rv$msg
    })

    rv <- reactiveValues(msg = NULL)

    observeEvent(input$submit, {
      validate(
        need(nchar(input$login)  > 0, "Введите логин"),
        need(nchar(input$pwd)    > 0, "Введите пароль"),
        need(input$pwd == input$pwd2, "Пароли не совпадают")
      )

      con <- get_db_con()
      dbExecute(con, "
        CREATE TABLE IF NOT EXISTS users (
          id            SERIAL PRIMARY KEY,
          username      TEXT UNIQUE,
          password_hash TEXT
        )
      ")
      hash_hex <- sodium::bin2hex(
        sodium::password_store(charToRaw(input$pwd))
      )

      ok <- tryCatch({
        dbExecute(con,
          "INSERT INTO users(username, password_hash) VALUES($1,$2)",
          params = list(input$login, hash_hex)
        )
        TRUE
      }, error = function(e) FALSE)

      dbDisconnect(con)
      rv$msg <- if (ok) "Аккаунт создан — войдите." else "Такой логин уже существует."
    })
  })
}
