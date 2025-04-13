read_msg <- function(bot, update) {
  if (!is.null(update$message$forward_from)) {
    forwarded_from <- update$message$forward_from$first_name
    cat(sprintf(
      "[Переслано от %s] %s\n", 
      forwarded_from,
      ifelse(!is.null(update$message$text), update$message$text, "[медиа]")
    ))
  } else {
    sender <- ifelse(!is.null(update$message$from$username),
                     paste0("@", update$message$from$username),
                     update$message$from$first_name
    )
    cat(sprintf(
      "[%s] %s\n", 
      sender,
      ifelse(!is.null(update$message$text), update$message$text, "[медиа]")
    ))
  }
}

read_msg_handler <- MessageHandler(read_msg)
dispatcher$add_handler(read_msg_handler)