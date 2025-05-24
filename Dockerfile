FROM rocker/r-ver:4.3.1

LABEL maintainer="valery"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libcurl4-openssl-dev \
    libxml2-dev \
    libpq-dev \
    git \
    libsodium-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN R -e "install.packages(c('remotes', 'renv'), repos = 'https://cloud.r-project.org/')"
RUN R -e "remotes::install_github('R-telegram/telegram.bot')"
RUN R -e "install.packages(c('future', 'parallelly', 'DBI', 'RPostgres', 'dplyr', 'stringr', \
    'stringi', 'lubridate', 'jsonlite', 'huggingfaceR', 'xml2', 'shiny', \
    'shinydashboard', 'sodium', 'DT', 'openssl', 'ggplot2', 'plotly'), \
    repos = 'https://cloud.r-project.org/')"

WORKDIR /app

COPY . /app/

RUN mkdir -p /app/logs
RUN mkdir -p /app/public

EXPOSE 3838

CMD ["Rscript", "cmd/app/main.R"]
