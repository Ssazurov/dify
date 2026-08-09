#!/bin/bash
# Скрипт для проверки и сохранения данных Dify при перезагрузках

set -e  # остановка при ошибке

# --- Конфигурация ---
PROJECT_DIR="/home/vector/dify/docker"
BACKUP_DIR="/home/vector/backups/dify"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$PROJECT_DIR/check_and_preserve.log"
DIFY_COMPOSE="$PROJECT_DIR/docker-compose.yaml"
ENV_FILE="$PROJECT_DIR/.env"

# Загружаем переменные из .env
source "$ENV_FILE"

# --- Функция логирования ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- 1. Проверка, что контейнеры запущены ---
log "Проверка статуса контейнеров..."
if ! docker ps | grep -q "docker-db_postgres-1"; then
    log "ОШИБКА: Контейнер PostgreSQL не запущен. Запускаем..."
    cd "$PROJECT_DIR" && docker compose up -d db_postgres
    sleep 10
fi

# --- 2. Проверка существования и типа тома PostgreSQL ---
log "Проверка тома PostgreSQL..."
VOLUME_NAME=$(docker inspect docker-db_postgres-1 | jq -r '.[0].Mounts[] | select(.Destination=="/var/lib/postgresql/data") | .Name' 2>/dev/null)
if [ -z "$VOLUME_NAME" ]; then
    log "⚠️ Том для PostgreSQL не найден или используется временный том!"
    log "Рекомендуется использовать именованный том. Проверьте docker-compose.yaml."
    log "Сейчас создадим постоянный том вручную..."
    docker volume create dify_db_data
    # Остановим контейнер, пересоздадим с новым томом (данные будут потеряны, если нет бэкапа)
    log "⚠️ ВНИМАНИЕ: Пересоздание тома приведёт к потере существующих данных!"
    read -p "Продолжить? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down
        # Заменяем в docker-compose том на именованный (если не прописан)
        sed -i 's/- postgres_data:/- dify_db_data:/g' "$DIFY_COMPOSE"
        docker compose up -d
        log "Том изменён, контейнер перезапущен."
    else
        log "Отмена пересоздания тома."
    fi
else
    log "✅ Используется постоянный том: $VOLUME_NAME"
    # Проверим, есть ли данные в БД
    DB_EXISTS=$(docker exec docker-db_postgres-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1 FROM apps LIMIT 1" 2>/dev/null || echo "0")
    if [ "$DB_EXISTS" == "1" ]; then
        log "✅ В БД есть данные (приложения). Настройки сохранены."
    else
        log "⚠️ В БД нет данных (таблица apps пуста). Возможно, данные потеряны."
        log "Попытка восстановить из последнего бэкапа..."
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/dify_backup_*.sql 2>/dev/null | head -n1)
        if [ -n "$LATEST_BACKUP" ]; then
            log "Найден бэкап: $LATEST_BACKUP. Восстанавливаю..."
            docker exec -i docker-db_postgres-1 psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < "$LATEST_BACKUP"
            log "✅ Восстановление завершено."
        else
            log "❌ Бэкап не найден. Данные восстановить невозможно."
        fi
    fi
fi

# --- 3. Создание бэкапа текущей БД (если есть данные) ---
log "Создание резервной копии БД в $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/dify_backup_$TIMESTAMP.sql"
docker exec docker-db_postgres-1 pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" > "$BACKUP_FILE"
if [ $? -eq 0 ]; then
    log "✅ Бэкап создан: $BACKUP_FILE"
    # Удаляем бэкапы старше 7 дней
    find "$BACKUP_DIR" -name "dify_backup_*.sql" -mtime +7 -delete
else
    log "❌ Ошибка создания бэкапа."
fi

# --- 4. Проверка автозапуска systemd ---
log "Проверка systemd-сервисов..."
SERVICE_FILE="/etc/systemd/system/dify-docker.service"
if [ -f "$SERVICE_FILE" ]; then
    log "✅ Сервисный файл существует: $SERVICE_FILE"
    if systemctl is-enabled --quiet dify-docker; then
        log "✅ Автозапуск включён."
    else
        log "⚠️ Автозапуск выключен. Включаем..."
        sudo systemctl enable dify-docker
    fi
    if systemctl is-active --quiet dify-docker; then
        log "✅ Сервис активен."
    else
        log "⚠️ Сервис не запущен. Запускаем..."
        sudo systemctl start dify-docker
    fi
else
    log "❌ Сервисный файл отсутствует. Создаю..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Dify Docker Compose
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=vector
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable dify-docker
    sudo systemctl start dify-docker
    log "✅ Сервис создан и запущен."
fi

# --- 5. Дополнительно: экспорт приложений (для страховки) ---
if [ -f "$PROJECT_DIR/export-apps.sh" ]; then
    log "Экспорт приложений через API (страховка)..."
    cd "$PROJECT_DIR"
    ./export-apps.sh > "$BACKUP_DIR/apps_export_$TIMESTAMP.json" 2>/dev/null || log "⚠️ Экспорт приложений не удался (возможно, нет ключа)."
fi

log "✅ Проверка завершена. Все настройки сохранены."
log "Для просмотра лога: cat $LOG_FILE"