msg_handler <- function(bot, update) {
  msg <- update$message
  if (is.null(msg)) return()

  if (!is.null(msg$forward_from)) {
    cat(sprintf(
      "[Переслано от %s] %s\n",
      msg$forward_from$first_name,
      if (!is.null(msg$text)) msg$text else "[медиа]"
    ))
  } else {
    sender <- if (!is.null(msg$from$username)) {
      paste0("@", msg$from$username)
    } else {
      msg$from$first_name
    }
    cat(sprintf(
      "[%s] %s\n",
      sender,
      if (!is.null(msg$text)) msg$text else "[медиа]"
    ))
  }

  if (!is.null(msg$chat$title)) {
    sender_name <- msg$from$first_name
    sender_username <- if (!is.null(msg$from$username)) {
      paste0("@", msg$from$username)
    } else {
      paste0("(", sender_name, ")")
    }
    cat(sprintf(
      "[Группа: %s] Отправитель: %s\nСообщение: %s\n\n",
      msg$chat$title,
      sender_username,
      if (!is.null(msg$text)) msg$text else "[медиа-файл]"
    ))
  }
}

handler <- MessageHandler(msg_handler)
dispatcher$add_handler(handler)
