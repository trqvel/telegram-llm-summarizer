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

ui <- dashboardPage(
  dashboardHeader(
    title = "Telegram-LLM",
    uiOutput("hdr_user")
  ),
  dashboardSidebar(
    sidebarMenu(
      id = "tabs",
      menuItem("Группы",  tabName = "groups", icon = icon("paper-plane")),
      menuItem("Статистика", tabName = "stats",  icon = icon("chart-line")),
      menuItem("Профиль", tabName = "profile", icon = icon("user"))
    )
  ),
  dashboardBody(uiOutput("body"))
)

server <- function(input, output, session) {

  output$hdr_user <- renderUI({
    if (is.null(user()))
      span()
    else
      tagList(
        span("Вы вошли как ", strong(user()$name)),
        actionLink("logout", "Выйти", icon = icon("sign-out-alt"))
      )
  })
  observeEvent(input$logout, user(NULL))

  output$body <- renderUI({
    if (is.null(user())) {
      fluidRow(
        column(6, login_ui("login")),
        column(6, register_ui("reg"))
      )
    } else {
      tabItems(
        tabItem("groups",
          h2("Мои группы"),
          textInput("chat_id", "ID или ссылка группы"),
          actionButton("add_group", "Добавить"),
          br(), DTOutput("tbl_groups")
        ),
        tabItem("stats",
          h2("Статистика"),
          dateRangeInput("dr", "Диапазон", start = Sys.Date()-7, end = Sys.Date()),
          DTOutput("tbl_stats")
        ),
        tabItem("profile", profile_ui("prof"))
      )
    }
  })

  login_server("login", user)
  register_server("reg")
  profile_server("prof", user)

  observeEvent(input$add_group, {
    req(user(), input$chat_id)
    con <- get_db_con()
    dbExecute(con, "
      CREATE TABLE IF NOT EXISTS user_groups(
        user_id INTEGER,
        chat_id TEXT,
        PRIMARY KEY(user_id, chat_id)
      )")
    dbExecute(con, "
      INSERT INTO user_groups(user_id, chat_id)
      VALUES($1,$2) ON CONFLICT DO NOTHING",
      params = list(user()$id, input$chat_id)
    )
    dbDisconnect(con)
  })

  groups_data <- reactivePoll(
    4000, session,
    checkFunc = function() {
      if (is.null(user())) return(0)
      con <- get_db_con()
      n  <- dbGetQuery(con,
             "SELECT COUNT(*) FROM user_groups WHERE user_id = $1",
             params = list(user()$id)
           )[[1]]
      dbDisconnect(con)
      n
    },
    valueFunc = function() {
      if (is.null(user())) return(data.frame())
      con <- get_db_con()
      df <- dbGetQuery(con,
             "SELECT chat_id FROM user_groups WHERE user_id = $1",
             params = list(user()$id)
           )
      dbDisconnect(con)
      df
    }
  )
  output$tbl_groups <- renderDT(groups_data(), options = list(pageLength = 5))

  output$tbl_stats <- renderDT({
    req(user())
    rng <- input$dr
    con <- get_db_con()
    df <- dbGetQuery(con, "
      SELECT c.chat_id,
             COUNT(*)         AS messages,
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
    df
  }, options = list(pageLength = 10))
}

shinyApp(ui, server)
