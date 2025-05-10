library(openai)

init_openai <- function() {
    key <- Sys.getenv("OPENAI_API_KEY")
    if (identical(key, "")) {
        stop("OPENAI_API_KEY is not set in .env")
    }
    Sys.setenv(OPENAI_API_KEY = key)
}

get_openai <- function() {
    init_openai()
    create_openai(api_key = Sys.getenv("OPENAI_API_KEY"))
}
