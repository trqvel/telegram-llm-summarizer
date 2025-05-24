#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

if [ ! -f .env ]; then
  error "Файл .env не найден. Создаем его с базовыми настройками..."
  
  cat > .env << EOF
TELEGRAM_BOT_TOKEN=your_token_here
HF_API_TOKEN=your_hf_token_here
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASS=postgres
DB_NAME=postgres
EOF

  warn "Создан .env файл с настройками по умолчанию."
  warn "Отредактируйте его, установив корректные значения для токенов и БД."
  exit 1
fi

if ! command -v docker &> /dev/null; then
  error "Docker не установлен. Установите Docker для продолжения."
  exit 1
fi

if ! command -v docker-compose &> /dev/null; then
  error "Docker Compose не установлен. Установите Docker Compose для продолжения."
  exit 1
fi

log "Создание необходимых директорий..."
mkdir -p data logs public

log "Проверка настроек БД..."
source .env

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ] || [ -z "$DB_NAME" ]; then
  error "Не все параметры БД установлены в файле .env"
  exit 1
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ "$TELEGRAM_BOT_TOKEN" == "your_token_here" ]; then
  warn "Токен Telegram бота не установлен или имеет значение по умолчанию"
fi

if [ -z "$HF_API_TOKEN" ] || [ "$HF_API_TOKEN" == "your_hf_token_here" ]; then
  warn "Токен HuggingFace API не установлен или имеет значение по умолчанию"
fi

log "Остановка предыдущих контейнеров (если есть)..."
docker-compose down

log "Сборка и запуск контейнеров..."
docker-compose up -d --build

log "Проверка статуса контейнеров..."
docker-compose ps

log "Ожидание готовности базы данных..."
sleep 5

log "Проверка логов контейнера приложения..."
docker-compose logs --tail=10 app

log "============================================="
log "Приложение запущено и доступно по адресу: http://localhost:3838"
log "БД PostgreSQL доступна по адресу: localhost:5432"
log "============================================="
log "Логи можно посмотреть командой: docker-compose logs -f app"
log "Для остановки используйте: docker-compose down"
log "Для перезапуска в случае проблем: ./run.sh"

log "Проверка доступности приложения..."
timeout 3 bash -c 'until curl -s http://localhost:3838 > /dev/null; do sleep 1; done' 2>/dev/null
if [ $? -eq 0 ]; then
  log "Приложение успешно запущено и доступно по адресу http://localhost:3838"
else
  warn "Не удалось подтвердить доступность приложения. Проверьте логи: docker-compose logs app"
fi 