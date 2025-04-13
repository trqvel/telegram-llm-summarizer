group_monitor <- function(bot, update) {
    if (!is.null(update$message$chat$title)) {
        group_name <- update$message$chat$title
        sender_name <- update$message$from$first_name
        sender_username <- ifelse(!is.null(update$message$from$username),
            paste0("@", update$message$from$username),
            paste0("(", sender_name, ")")
        )

        cat(sprintf(
            "[Группа: %s] Отправитель: %s\nСообщение: %s\n\n",
            group_name,
            sender_username,
            ifelse(!is.null(update$message$text), update$message$text, "[медиа-файл]")
        ))
    }
}

group_handler <- MessageHandler(group_monitor)
dispatcher$add_handler(group_handler)
