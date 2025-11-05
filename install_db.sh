if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

POSTGRES_PASS=$1
REDIS_PASS=$1

if [ -z "$POSTGRES_PASS" ]; then
  echo "❌ Укажи пароль!"
  echo "Пример: sudo ./install_db.sh 123456789"
  exit 1
fi

POSTGRES_USER="postgres"
DB_NAME="tg_bot"

REDIS_USER="default"

echo "Начинаем установку PostgreSQL и Redis..."

sudo apt update -y

# --- Установка PostgreSQL ---
if ! command -v psql &> /dev/null; then
  echo "Устанавливаем PostgreSQL..."
  sudo apt install -y postgresql postgresql-contrib
else
  echo "PostgreSQL уже установлен."
fi

# --- Настройка PostgreSQL ---
echo "Настраиваем PostgreSQL..."

# Включаем автозапуск
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Меняем пароль пользователю postgres
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASS';"

# Создаём базу tg_bot, если не существует
if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
  sudo -u postgres createdb "$DB_NAME"
  echo "База данных $DB_NAME создана."
else
  echo "База $DB_NAME уже существует."
fi

# --- Установка Redis ---
if ! command -v redis-server &> /dev/null; then
  echo "Устанавливаем Redis..."
  sudo apt install -y redis-server
else
  echo "Redis уже установлен."
fi

# --- Настройка Redis ---
echo "⚙️ Настраиваем Redis..."

REDIS_CONF="/etc/redis/redis.conf"

# Меняем конфиг (устанавливаем пароль и логин)
sudo sed -i "s/^# requirepass .*/requirepass $REDIS_PASS/" "$REDIS_CONF"

# Если Redis >=7, добавим ACL для пользователя default
if grep -q "user default" "$REDIS_CONF"; then
  sudo sed -i "s/^user default .*/user default on >$REDIS_PASS allcommands allkeys/" "$REDIS_CONF"
else
  echo "user default on >$REDIS_PASS allcommands allkeys" | sudo tee -a "$REDIS_CONF" >/dev/null
fi

# Включаем автозапуск Redis
sudo systemctl enable redis-server
sudo systemctl restart redis-server

echo "Redis настроен."

# --- Проверка ---
echo "Проверяем подключение к PostgreSQL..."
PGPASSWORD=$POSTGRES_PASS psql -h localhost -U $POSTGRES_USER -d $DB_NAME -c "\l" >/dev/null && echo "PostgreSQL работает."

echo "Проверяем подключение к Redis..."
if redis-cli -a "$REDIS_PASS" ping | grep -q "PONG"; then
  echo "Redis работает и принимает пароль."
else
  echo "Ошибка подключения к Redis."
fi

echo ""
echo "Установка завершена!"
echo "-------------------------------------"
echo "PostgreSQL:"
echo "Хост: localhost"
echo "Пользователь: $POSTGRES_USER"
echo "Пароль: $POSTGRES_PASS"
echo "База: $DB_NAME"
echo ""
echo "Redis:"
echo "Логин: $REDIS_USER"
echo "Пароль: $REDIS_PASS"
echo "Хост: localhost"
echo "-------------------------------------"
