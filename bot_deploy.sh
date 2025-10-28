#!/bin/bash
# Скрипт для деплоя бота из git-репозитория без использования контейнера
# Usage: ./deploy.sh https://github.com/you/mybot.git [branch]


REPO_URL=$1
BRANCH=${2:-master}
BASE_DIR=/home/bot

if [ -z "$REPO_URL" ]; then
  echo "❌ Укажи ссылку на репозиторий. Пример:"
  echo "   ./deploy.sh https://github.com/you/mybot.git"
  exit 1
fi

BOT_NAME=$(basename -s .git "$REPO_URL")
# BOT_DIR=$BASE_DIR/$BOT_NAME
BOT_DIR=$BASE_DIR

# --- Клонирование или инициализация git ---
echo "🚀 Разворачиваем бота '$BOT_NAME' из $REPO_URL (ветка: $BRANCH)..."

if [ ! -d "$BOT_DIR" ]; then
  echo "📁 Папка не найдена — создаём $BOT_DIR..."
  mkdir -p "$BOT_DIR"

if ! command -v python3.11 &> /dev/null; then
  echo "🐍 Python 3.11 не найден — устанавливаем..."
  sudo add-apt-repository ppa:deadsnakes/ppa
  sudo apt update
  sudo apt install python3.11-full
else
  echo "✅ Python 3.11 уже установлен." 
python3.11 -m venv "$BOT_DIR"

cd "$BOT_DIR"
echo "🌱 Инициализируем git..."
git init
git remote add main "$REPO_URL"
git pull main "$BRANCH"

# --- Установка зависимостей ---
if ! command -v uv &> /dev/null; then
    echo "📦 Устанавливаем uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi


if [ -f "uv.lock" ]; then
  echo "⚡ Обнаружен uv.lock"
  uv sync --frozen
elif [ -f "requirements.txt" ]; then
  echo "🐍 Обнаружен requirements.txt"
  uv pip install -r requirements.txt
else
  echo "⚠️ Не найден ни requirements.txt, ни uv.lock — пропускаем установку зависимостей."
fi

# SERVICE_FILE=/etc/systemd/system/$BOT_NAME.service
SERVICE_FILE=/etc/systemd/system/bot.service

# --- Создание systemd-сервиса ---
echo "⚙️ Создаём systemd-сервис..."
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=$BOT_NAME bot
After=syslog.target
After=network.target

[Service]
User=root
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/bin/python /home/bot/bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable bot
sudo systemctl restart restart

if grep -q "arq" requirements.txt 2>/dev/null || grep -q "arq" pyproject.toml 2>/dev/null || grep -q "arq" uv.lock 2>/dev/null; then
  echo "🧩 Обнаружен arq — создаём сервис для фонового воркера..."
  SCHEDULER_FILE=/etc/systemd/system/task.service
  sudo bash -c "cat > $SCHEDULER_FILE" <<EOF
[Unit]
Description=${BOT_NAME} ARQ Scheduler
After=syslog.target
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$BOT_DIR
ExecStart=$BOT_DIR/bin/arq app.scheduler.worker.WorkerSettings
RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable task
  sudo systemctl restart task
fi

echo "✅ Бот $BOT_NAME успешно запущен!"
echo "📋 Логи: sudo journalctl -u $BOT_NAME -f"
