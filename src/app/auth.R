library(shiny)
library(DBI)
library(RPostgres)
library(openssl)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

auth_ui <- function(id) {
  ns <- NS(id)
  div(class = "auth-form",
    div(class = "form-group",
      textInput(ns("login"), "Логин", 
                placeholder = "Введите имя пользователя",
                width = "100%")
    ),
    div(class = "form-group",
      passwordInput(ns("pwd"), "Пароль", 
                    placeholder = "Введите пароль",
                    width = "100%")
    ),
    div(class = "form-group",
      actionButton(ns("go"), "Войти", 
                  class = "btn-primary btn-block",
                  width = "100%")
    ),
    uiOutput(ns("error_msg"))
  )
}

auth_server <- function(id, user, session) {
  moduleServer(id, function(input, output, session) {
    
    rv <- reactiveValues(error_msg = NULL)
    
    output$error_msg <- renderUI({
      if (!is.null(rv$error_msg)) {
        div(class = "alert alert-danger", 
            icon("exclamation-circle"), 
            rv$error_msg)
      }
    })
    
    observeEvent(input$go, {
      req(input$login, input$pwd)
      
      if (nchar(input$login) == 0 || nchar(input$pwd) == 0) {
        rv$error_msg <- "Заполните все поля"
        return()
      }
      
      tryCatch({
        con <- get_db_con()
        info <- dbGetQuery(con,
          "SELECT id, username, password_hash FROM users WHERE username = $1",
          params = list(input$login)
        )
        dbDisconnect(con)
  
        if (nrow(info) == 1) {
          valid <- FALSE
          
          tryCatch({
            stored_hash <- info$password_hash[1]
            parts <- strsplit(stored_hash, "\\$")[[1]]
            if (length(parts) == 2) {
              salt <- parts[1]
              hash_value <- parts[2]
              
              salted_pwd <- paste0(input$pwd, salt)
              computed_hash <- openssl::sha256(salted_pwd)
              
              valid <- (computed_hash == hash_value)
            }
          }, error = function(e) {
            valid <- FALSE
          })
          
          if (isTRUE(valid)) {
            user(list(id = info$id[1], name = info$username[1]))
            rv$error_msg <- NULL
            session$reload()
            return()
          }
        }
        rv$error_msg <- "Неверный логин или пароль"
      }, error = function(e) {
        rv$error_msg <- paste("Ошибка при попытке входа:", e$message)
      })
    })
  })
}
