library(shiny)
library(DBI)
library(RPostgres)
library(openssl)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

reg_ui <- function(id) {
  ns <- NS(id)
  div(class = "auth-form",
    div(class = "form-group",
      textInput(ns("login"), "Логин", 
                placeholder = "Придумайте имя пользователя",
                width = "100%")
    ),
    div(class = "form-group",
      passwordInput(ns("pwd"), "Пароль", 
                    placeholder = "Придумайте пароль",
                    width = "100%")
    ),
    div(class = "form-group",
      passwordInput(ns("pwd2"), "Повтор пароля", 
                    placeholder = "Повторите пароль",
                    width = "100%")
    ),
    div(class = "form-group",
      actionButton(ns("submit"), "Создать аккаунт", 
                  class = "btn-primary btn-block",
                  width = "100%")
    ),
    uiOutput(ns("msg_ui"))
  )
}

reg_server <- function(id, session) {
  moduleServer(id, function(input, output, session) {
    
    rv <- reactiveValues(msg = NULL, msg_type = NULL)
    
    output$msg_ui <- renderUI({
      if (!is.null(rv$msg)) {
        div(class = paste0("alert alert-", rv$msg_type), 
            if(rv$msg_type == "danger") icon("exclamation-circle") else icon("check-circle"),
            rv$msg)
      }
    })
    
    observeEvent(input$submit, {
      if (nchar(input$login) == 0) {
        rv$msg <- "Введите логин"
        rv$msg_type <- "danger"
        return()
      }
      
      if (nchar(input$pwd) == 0) {
        rv$msg <- "Введите пароль"
        rv$msg_type <- "danger"
        return()
      }
      
      if (input$pwd != input$pwd2) {
        rv$msg <- "Пароли не совпадают"
        rv$msg_type <- "danger"
        return()
      }

      con <- get_db_con()
      dbExecute(con, "
        CREATE TABLE IF NOT EXISTS users (
          id            SERIAL PRIMARY KEY,
          username      TEXT UNIQUE,
          password_hash TEXT
        )
      ")
      
      hash <- tryCatch({
        salt <- openssl::rand_bytes(16)
        salted_pwd <- paste0(input$pwd, openssl::base64_encode(salt))
        hash_result <- openssl::sha256(salted_pwd)
        paste0(
          openssl::base64_encode(salt),
          "$",
          hash_result
        )
      }, error = function(e) {
        rv$msg <- "Ошибка при хешировании пароля"
        rv$msg_type <- "danger"
        return(NULL)
      })
      
      if (is.null(hash)) {
        dbDisconnect(con)
        return()
      }

      ok <- tryCatch({
        dbExecute(con,
          "INSERT INTO users(username, password_hash) VALUES($1,$2)",
          params = list(input$login, hash)
        )
        TRUE
      }, error = function(e) FALSE)

      dbDisconnect(con)
      
      if (ok) {
        rv$msg <- "Аккаунт успешно создан! Теперь вы можете войти."
        rv$msg_type <- "success"
        updateTextInput(session, "login", value = "")
        updateTextInput(session, "pwd", value = "")
        updateTextInput(session, "pwd2", value = "")
        session$sendCustomMessage("switchToLogin", TRUE)
      } else {
        rv$msg <- "Логин уже занят. Пожалуйста, выберите другой."
        rv$msg_type <- "danger"
      }
    })
  })
}
