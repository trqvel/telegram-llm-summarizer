library(shiny)
library(shinydashboard)
library(DT)
library(DBI)
library(RPostgres)

root_dir <- normalizePath(file.path(dirname(getwd()), ".."))
source(file.path(root_dir, "src/app/auth.R"))
source(file.path(root_dir, "src/app/reg.R"))
source(file.path(root_dir, "src/app/profile.R"))
source(file.path(root_dir, "src/db/connection_db.R"))

user <- reactiveVal(NULL)

initialize_db <- function() {
  con <- get_db_con()
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS users (
      id            SERIAL PRIMARY KEY,
      username      TEXT UNIQUE,
      password_hash TEXT
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS user_groups(
      user_id INTEGER,
      chat_id TEXT,
      PRIMARY KEY(user_id, chat_id)
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS raw_msgs(
      update_id BIGINT PRIMARY KEY,
      update_json TEXT,
      processed BOOLEAN DEFAULT FALSE
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS clean_msgs(
      update_id BIGINT PRIMARY KEY,
      chat_id BIGINT,
      user_id BIGINT,
      ts TIMESTAMP,
      text_clean TEXT
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS sentiments(
      update_id BIGINT PRIMARY KEY,
      sentiment TEXT
    )
  ")
  
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS summaries(
      chat_id BIGINT,
      period_start TIMESTAMP,
      period_end TIMESTAMP,
      summary TEXT,
      PRIMARY KEY(chat_id, period_start)
    )
  ")
  
  dbDisconnect(con)
}

ui <- function(req) {
  if (is.null(isolate(user()))) {
    fluidPage(
      tags$head(
        tags$style(HTML("
          body {
            background-color: #f5f8fa;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
          }
          .auth-container {
            max-width: 900px;
            margin: 100px auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
          }
          .auth-header {
            text-align: center;
            margin-bottom: 30px;
            color: #2980b9;
          }
          .form-group {
            margin-bottom: 20px;
          }
          .btn-primary {
            background-color: #2980b9;
            border-color: #2980b9;
            width: 100%;
            padding: 10px;
            font-size: 16px;
            margin-top: 10px;
          }
          .nav-tabs {
            margin-bottom: 30px;
            border-bottom: 1px solid #ddd;
          }
          .nav-tabs > li > a {
            color: #555;
            font-size: 18px;
          }
          .nav-tabs > li.active > a {
            color: #2980b9;
            font-weight: bold;
          }
        ")),
        tags$script(HTML("
          Shiny.addCustomMessageHandler('switchToLogin', function(message) {
            $('a[data-value=\"login\"]').tab('show');
          });
        "))
      ),
      div(class = "auth-container",
        h1(class = "auth-header", "Telegram-LLM Summarizer"),
        tabsetPanel(id = "authTabs", 
          tabPanel("Вход", value = "login", 
            auth_ui("auth")
          ),
          tabPanel("Регистрация", value = "register", 
            reg_ui("reg")
          )
        )
      )
    )
  } else {
    dashboardPage(
      dashboardHeader(
        title = "Telegram-LLM",
        tags$li(class = "dropdown",
          tags$a(href = "#", 
            span("Вы вошли как ", strong(isolate(user()$name))),
            style = "padding: 15px;"
          )
        ),
        tags$li(class = "dropdown",
          actionLink("logout", "Выйти", icon = icon("sign-out-alt"))
        )
      ),
      dashboardSidebar(
        sidebarMenu(
          id = "tabs",
          menuItem("Группы",  tabName = "groups", icon = icon("paper-plane")),
          menuItem("Статистика", tabName = "stats",  icon = icon("chart-line")),
          menuItem("Профиль", tabName = "profile", icon = icon("user"))
        )
      ),
      dashboardBody(
        tabItems(
          tabItem("groups",
            h2("Мои группы"),
            div(class = "row",
              div(class = "col-md-6",
                div(class = "box box-primary",
                  div(class = "box-header", h3(class = "box-title", "Добавить группу")),
                  div(class = "box-body",
                    textInput("chat_id", "ID или ссылка группы", 
                              placeholder = "Например: -1001234567890 или @groupname"),
                    helpText("Укажите числовой ID группы (начинается с минуса) или юзернейм (через @)"),
                    actionButton("add_group", "Добавить", class = "btn-primary")
                  )
                )
              )
            ),
            div(class = "row",
              div(class = "col-md-12",
                div(class = "box box-primary",
                  div(class = "box-header", h3(class = "box-title", "Список групп")),
                  div(class = "box-body", DTOutput("tbl_groups"))
                )
              )
            )
          ),
          tabItem("stats",
            h2("Статистика"),
            div(class = "row",
              div(class = "col-md-4",
                div(class = "box box-primary",
                  div(class = "box-header", h3(class = "box-title", "Фильтр")),
                  div(class = "box-body",
                    dateRangeInput("dr", "Выберите период", 
                                  start = Sys.Date()-7, end = Sys.Date())
                  )
                )
              )
            ),
            div(class = "row",
              div(class = "col-md-12",
                div(class = "box box-primary",
                  div(class = "box-header", h3(class = "box-title", "Активность в группах")),
                  div(class = "box-body", DTOutput("tbl_stats"))
                )
              )
            ),
            div(class = "row",
              div(class = "col-md-12",
                div(class = "box box-info",
                  div(class = "box-header", h3(class = "box-title", "Информация")),
                  div(class = "box-body", 
                    p("Если статистика пуста, необходимо:"),
                    tags$ol(
                      tags$li("Добавить бота в группу как администратора"), 
                      tags$li("Подождать некоторое время, пока соберутся данные"),
                      tags$li("Активность появится автоматически после обработки сообщений")
                    )
                  )
                )
              )
            )
          ),
          tabItem("profile", 
            h2("Настройки профиля"),
            profile_ui("prof")
          )
        )
      )
    )
  }
}

server <- function(input, output, session) {
  
  initialize_db()
  
  observeEvent(input$logout, {
    user(NULL)
    session$reload()
  })

  observe({
    req(input$authTabs)
    if(input$authTabs == "login") {
      auth_server("auth", user, session)
    } else if(input$authTabs == "register") {
      reg_server("reg", session)
    }
  })
  
  profile_server("prof", user)

  observeEvent(input$add_group, {
    req(user(), input$chat_id)
    
    chat_id <- input$chat_id
    
    if (grepl("^@", chat_id)) {
      chat_id <- gsub("^@", "", chat_id)
    }
    
    tryCatch({
      con <- get_db_con()
      dbExecute(con, "
        INSERT INTO user_groups(user_id, chat_id)
        VALUES($1,$2) ON CONFLICT DO NOTHING",
        params = list(user()$id, chat_id)
      )
      dbDisconnect(con)
      updateTextInput(session, "chat_id", value = "")
      showNotification("Группа успешно добавлена", type = "message")
    }, error = function(e) {
      showNotification(paste("Ошибка при добавлении группы:", e$message), type = "error")
    })
  })

  groups_data <- reactive({
    if (is.null(user())) return(data.frame())
    
    invalidateLater(5000)
    
    tryCatch({
      con <- get_db_con()
      df <- dbGetQuery(con,
             "SELECT chat_id FROM user_groups WHERE user_id = $1",
             params = list(user()$id)
           )
      dbDisconnect(con)
      df
    }, error = function(e) {
      data.frame()
    })
  })
  
  output$tbl_groups <- renderDT({
    req(user())
    df <- groups_data()
    
    if (nrow(df) == 0) {
      df <- data.frame(chat_id = character(0))
    }
    
    datatable(df,
      colnames = c("ID/Имя группы"),
      options = list(
        pageLength = 10,
        language = list(
          search = "Поиск:",
          lengthMenu = "Показать _MENU_ записей",
          info = "Записи с _START_ до _END_ из _TOTAL_",
          emptyTable = "Нет добавленных групп",
          paginate = list(
            first = "Первая",
            last = "Последняя",
            "next" = "Следующая", 
            previous = "Предыдущая"
          )
        )
      )
    )
  })

  output$tbl_stats <- renderDT({
    req(user())
    rng <- input$dr
    
    tryCatch({
      con <- get_db_con()
      df <- dbGetQuery(con, "
        SELECT c.chat_id,
               COUNT(*) AS messages,
               COUNT(DISTINCT user_id) AS authors
        FROM clean_msgs c
        JOIN user_groups g
          ON g.chat_id::bigint = c.chat_id
        WHERE g.user_id = $1
          AND c.ts BETWEEN $2 AND $3
        GROUP BY c.chat_id
        ORDER BY messages DESC
      ", params = list(user()$id,
                       as.character(rng[1]),
                       as.character(rng[2])))
      dbDisconnect(con)
      
      if (nrow(df) == 0) {
        df <- data.frame(
          chat_id = character(0),
          messages = integer(0),
          authors = integer(0)
        )
      }
      
      colnames(df) <- c("ID группы", "Сообщений", "Авторов")
      df
    }, error = function(e) {
      data.frame(
        `ID группы` = character(0),
        `Сообщений` = integer(0),
        `Авторов` = integer(0)
      )
    })
  }, options = list(
    pageLength = 10,
    language = list(
      search = "Поиск:",
      emptyTable = "Нет данных для отображения",
      lengthMenu = "Показать _MENU_ записей",
      info = "Записи с _START_ до _END_ из _TOTAL_",
      paginate = list(
        first = "Первая",
        last = "Последняя",
        "next" = "Следующая",
        previous = "Предыдущая"
      )
    )
  ))
}

shinyApp(ui, server)
