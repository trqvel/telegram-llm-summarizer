library(dplyr)
library(jsonlite)
library(stringr)
library(lubridate)

if (!requireNamespace("stringdist", quietly = TRUE)) {
  install.packages("stringdist")
}
library(stringdist)

source("src/db/connection.R")
con <- get_db_con()

word_frequency <- list(
  high_freq = c("привет", "спасибо", "хорошо", "окей", "да", "нет", "сегодня", "завтра", "время"),
  medium_freq = c("здравствуйте", "пожалуйста", "нормально", "согласен", "понятно", "интересно", "человек", "очень", "информация", "сейчас", "потом", "работа"),
  low_freq = c("договорились", "возможно", "вероятно", "предполагаю", "гарантирую", "организовать", "обсудить", "результат", "предложение", "решение", "выполнить", "подготовить")
)

word_contexts <- list(
  c("очень", "хорошо"),
  c("большое", "спасибо"),
  c("хорошего", "дня"),
  c("с", "уважением"),
  c("в", "общем"),
  c("на", "самом", "деле"),
  c("до", "свидания"),
  c("как", "дела"),
  c("в", "любом", "случае")
)

all_words <- c(
  word_frequency$high_freq,
  word_frequency$medium_freq,
  word_frequency$low_freq
)

normalize_text <- function(text) {
  if (is.null(text) || text == "") return("")
  
  text <- str_remove_all(text, "<[^>]+>")
  text <- str_remove_all(text, "https?://\\S+")
  
  words <- unlist(str_split(text, "\\s+"))
  
  for (context in word_contexts) {
    context_length <- length(context)
    if (length(words) >= context_length) {
      for (i in 1:(length(words) - context_length + 1)) {
        window <- words[i:(i+context_length-1)]
        avg_distance <- mean(sapply(1:context_length, function(j) {
          if (nchar(window[j]) < 3) return(1)
          clean_word <- str_remove_all(window[j], "[.,!?:;]")
          min(stringdist(tolower(clean_word), tolower(context[j]), method = "jw"))
        }))
        if (avg_distance < 0.25) {
          for (j in 1:context_length) {
            words[i+j-1] <- context[j]
          }
        }
      }
    }
  }
  
  corrected_words <- sapply(1:length(words), function(i) {
    word <- words[i]
    if (nchar(word) < 3 || grepl("\\d", word) || word %in% c(".", ",", "!", "?", ":", ";")) {
      return(word)
    }
    clean_word <- str_remove_all(word, "[.,!?:;]")
    distances <- sapply(all_words, function(dict_word) {
      dist <- stringdist(tolower(clean_word), tolower(dict_word), method = "jw")
      if (dict_word %in% word_frequency$high_freq) {
        dist <- dist * 0.7
      } else if (dict_word %in% word_frequency$medium_freq) {
        dist <- dist * 0.85
      }
      if (i > 1 && i < length(words)) {
        for (context in word_contexts) {
          if (length(context) >= 2) {
            if (dict_word == context[1] && i < length(words)) {
              next_word_dist <- stringdist(tolower(words[i+1]), tolower(context[2]), method = "jw")
              if (next_word_dist < 0.3) dist <- dist * 0.8
            }
            if (length(context) >= 2 && dict_word == context[2] && i > 1) {
              prev_word_dist <- stringdist(tolower(words[i-1]), tolower(context[1]), method = "jw")
              if (prev_word_dist < 0.3) dist <- dist * 0.8
            }
          }
        }
      }
      return(dist)
    })
    min_dist <- min(distances)
    best_match <- all_words[which.min(distances)]
    if (min_dist < 0.3) {
      punctuation <- str_extract(word, "[.,!?:;]+$")
      if (!is.na(punctuation)) {
        return(paste0(best_match, punctuation))
      } else {
        return(best_match)
      }
    } else {
      return(word)
    }
  })
  
  text <- paste(corrected_words, collapse = " ")
  text <- str_replace_all(text, "\\!{2,}", "!")
  text <- str_replace_all(text, "\\?{2,}", "?")
  text <- str_replace_all(text, "\\.{2,3}", "…")
  text <- str_replace_all(text, "\\.{4,}", "…")
  text <- str_replace_all(text, "\\,{2,}", ",")
  text <- str_replace_all(text, "([.,!?:;])([^\\s])", "\\1 \\2")
  text <- str_replace_all(text, "\\s+([.,!?:;])", "\\1")
  if (!str_detect(text, "[.!?]$") && nchar(text) > 0) {
    text <- paste0(text, ".")
  }
  text <- str_squish(text)
  if (nchar(text) > 0) {
    first_char <- str_sub(text, 1, 1)
    rest_text <- str_sub(text, 2)
    text <- paste0(toupper(first_char), rest_text)
  }
  return(text)
}

if (!dbExistsTable(con, "clean_msgs")) {
  dbExecute(con, "
    CREATE TABLE clean_msgs (
      update_id   BIGINT PRIMARY KEY REFERENCES raw_updates(update_id),
      chat_id     BIGINT,
      chat_title  TEXT,
      user_id     BIGINT,
      user_name   TEXT,
      ts          TIMESTAMP,
      text_raw    TEXT,
      text_clean  TEXT
    )"
  )
}

raws <- dbGetQuery(con, "
  SELECT update_id, update_json
  FROM raw_updates
  WHERE update_id NOT IN (SELECT update_id FROM clean_msgs)"
)

if (nrow(raws) > 0) {
  clean_list <- lapply(raws$update_json, function(j) {
    u <- fromJSON(j)
    m <- u$message
    data.frame(
      update_id   = u$update_id,
      chat_id     = m$chat$id,
      chat_title  = ifelse(is.null(m$chat$title), NA, m$chat$title),
      user_id     = m$from$id,
      user_name   = ifelse(is.null(m$from$username), m$from$first_name, m$from$username),
      ts          = as_datetime(m$date),
      text_raw    = ifelse(is.null(m$text), NA, m$text),
      text_clean  = normalize_text(ifelse(is.null(m$text), "", m$text)),
      stringsAsFactors = FALSE
    )
  })

  clean_df <- bind_rows(clean_list)
  dbWriteTable(con, "clean_msgs", clean_df, append = TRUE)
  cat(sprintf("Обработано %d сообщений\n", nrow(clean_df)))
} else {
  cat("Новых сообщений для обработки не найдено\n")
}

dbDisconnect(con)
