library(shiny)
library(DBI)
library(RPostgres)
library(openssl)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/db/connection_db.R"))

profile_ui <- function(id) {
  ns <- NS(id)
  div(class = "row",
    div(class = "col-md-6",
      div(class = "box box-primary",
        div(class = "box-header", h3(class = "box-title", "Изменение данных профиля")),
        div(class = "box-body",
          div(class = "form-group",
            textInput(ns("login"), "Логин", 
                    placeholder = "Новое имя пользователя",
                    width = "100%")
          ),
          div(class = "form-group",
            passwordInput(ns("pwd"), "Новый пароль (необязательно)", 
                        placeholder = "Оставьте пустым, чтобы не менять",
                        width = "100%")
          ),
          div(class = "form-group",
            passwordInput(ns("pwd2"), "Повтор нового пароля", 
                        placeholder = "Повторите новый пароль",
                        width = "100%")
          ),
          div(class = "form-group",
            actionButton(ns("save"), "Сохранить изменения", 
                        class = "btn-primary")
          ),
          uiOutput(ns("status_msg"))
        )
      )
    )
  )
}

profile_server <- function(id, user) {
  moduleServer(id, function(input, output, session) {

    observe({
      req(user())
      updateTextInput(session, "login", value = user()$name)
    })

    rv <- reactiveValues(msg = NULL, msg_type = NULL)
    
    output$status_msg <- renderUI({
      if (!is.null(rv$msg)) {
        div(class = paste0("alert alert-", rv$msg_type), 
            if(rv$msg_type == "danger") icon("exclamation-circle") else icon("check-circle"),
            rv$msg)
      }
    })

    observeEvent(input$save, {
      req(user())
      
      if (nchar(input$login) == 0) {
        rv$msg <- "Логин не может быть пустым"
        rv$msg_type <- "danger"
        return()
      }
      
      if (nchar(input$pwd) > 0 && input$pwd != input$pwd2) {
        rv$msg <- "Пароли не совпадают"
        rv$msg_type <- "danger"
        return()
      }
      
      if (input$login != user()$name) {
        tryCatch({
          con <- get_db_con()
          result <- dbGetQuery(con, "
            SELECT COUNT(*) FROM users WHERE username = $1 AND id != $2
          ", params = list(input$login, user()$id))
          dbDisconnect(con)
          
          if (result[[1]] > 0) {
            rv$msg <- "Этот логин уже занят другим пользователем"
            rv$msg_type <- "danger"
            return()
          }
        }, error = function(e) {
          rv$msg <- "Ошибка при проверке логина"
          rv$msg_type <- "danger"
          return()
        })
      }
      
      tryCatch({
        con <- get_db_con()
        
        if (nchar(input$pwd) > 0) {
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
          
          dbExecute(con, "
            UPDATE users
            SET username = $1, password_hash = $2
            WHERE id = $3
          ", params = list(input$login, hash, user()$id))
        } else {
          dbExecute(con, "
            UPDATE users SET username = $1 WHERE id = $2
          ", params = list(input$login, user()$id))
        }
        dbDisconnect(con)
        
        user(modifyList(user(), list(name = input$login)))
        
        rv$msg <- "Данные профиля успешно обновлены"
        rv$msg_type <- "success"
        
        updateTextInput(session, "pwd", value = "")
        updateTextInput(session, "pwd2", value = "")
      }, error = function(e) {
        rv$msg <- paste("Ошибка при обновлении профиля:", e$message)
        rv$msg_type <- "danger"
      })
    })
  })
}
