library(shiny)
library(DBI)
library(RPostgres)
library(sodium)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

profile_ui <- function(id) {
  ns <- NS(id)
  tagList(
    h3("Профиль"),
    textInput(ns("login"), "Новый логин"),
    passwordInput(ns("pwd"),  "Новый пароль (необязательно)"),
    passwordInput(ns("pwd2"), "Повтор пароля"),
    actionButton(ns("save"), "Сохранить"),
    br(), verbatimTextOutput(ns("msg"))
  )
}

profile_server <- function(id, user) {
  moduleServer(id, function(input, output, session) {

    observe({
      req(user())
      updateTextInput(session, "login", value = user()$name)
    })

    output$msg <- renderText({ rv$msg })
    rv <- reactiveValues(msg = NULL)

    observeEvent(input$save, {
      req(user())
      validate(
        need(nchar(input$login) > 0, "Логин не может быть пустым"),
        if (nchar(input$pwd) > 0)
          need(input$pwd == input$pwd2, "Пароли не совпадают") else TRUE
      )
      con <- get_db_con()
      if (nchar(input$pwd) > 0) {
        hash_hex <- sodium::bin2hex(
          sodium::password_store(charToRaw(input$pwd))
        )
        dbExecute(con, "
          UPDATE users
          SET username = $1, password_hash = $2
          WHERE id = $3
        ", params = list(input$login, hash_hex, user()$id))
      } else {
        dbExecute(con, "
          UPDATE users SET username = $1 WHERE id = $2
        ", params = list(input$login, user()$id))
      }
      dbDisconnect(con)
      user(modifyList(user(), list(name = input$login)))
      rv$msg <- "Данные обновлены."
    })
  })
}
