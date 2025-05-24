library(httr)
library(jsonlite)

.hf_token <- Sys.getenv("HF_API_TOKEN")
if (identical(.hf_token, "")) stop("HF_API_TOKEN is not set in .env")

.hf_model <- Sys.getenv("HF_MODEL_ID", unset = "meta-llama/Llama-2-7b-chat-hf")

hf_complete <- function(prompt, max_tokens = 256) {
  url <- paste0("https://api-inference.huggingface.co/models/", .hf_model)
  
  message(paste("Отправка запроса к модели:", .hf_model))
  message(paste("Начало промпта:", substr(prompt, 1, 50), "..."))
  
  response <- tryCatch({
    POST(
      url,
      add_headers(
        "Authorization" = paste("Bearer", .hf_token),
        "Content-Type" = "application/json"
      ),
      body = toJSON(list(
        inputs = prompt,
        parameters = list(max_new_tokens = max_tokens)
      ), auto_unbox = TRUE),
      encode = "json"
    )
  }, error = function(e) {
    message(paste("Ошибка при отправке запроса:", e$message))
    stop(e$message)
  })
  
  if (status_code(response) != 200) {
    error_message <- paste("Ошибка API:", status_code(response), content(response, "text", encoding = "UTF-8"))
    message(error_message)
    if (grepl("тональност", tolower(prompt))) {
      return("нейтральная")
    } else {
      return("Не удалось создать сводку из-за ошибки API")
    }
  }
  
  result <- content(response, "parsed")
  
  if (is.list(result) && !is.null(result[[1]]$generated_text)) {
    text <- result[[1]]$generated_text
    text <- sub(prompt, "", text, fixed = TRUE)
    return(trimws(text))
  } else {
    message("Странный формат ответа от API:")
    message(toJSON(result, auto_unbox = TRUE, pretty = TRUE))
    if (grepl("тональност", tolower(prompt))) {
      return("нейтральная")
    } else {
      return("Сводка сообщений недоступна")
    }
  }
}
