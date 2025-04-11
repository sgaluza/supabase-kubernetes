#!/bin/sh

# Скрипт для установки extended attributes для всех файлов в хранилище Supabase

# Проверяем, что переданы все необходимые параметры
if [ $# -lt 2 ]; then
  echo "Использование: $0 <имя_пода> <неймспейс>"
  exit 1
fi

POD_NAME=$1
NAMESPACE=$2

echo "=== Установка Extended Attributes для всех файлов в Supabase Storage ==="
echo "Под: $POD_NAME"
echo "Неймспейс: $NAMESPACE"
echo "=============================================="

# Проверка существования пода
echo "Проверка существования пода..."
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &> /dev/null; then
  echo "Ошибка: Под $POD_NAME не найден в неймспейсе $NAMESPACE"
  exit 1
fi

# Создание временного скрипта
TEMP_SCRIPT=$(mktemp)
echo "Создан временный скрипт: $TEMP_SCRIPT"

# Создание скрипта для выполнения в поде
cat > "$TEMP_SCRIPT" << 'EOF'
#!/bin/sh

# Устанавливаем PostgreSQL клиент, если его нет
if ! which psql > /dev/null 2>&1; then
  echo "Установка PostgreSQL клиента..."
  apk add --no-cache postgresql-client
fi

# Устанавливаем attr, если его нет
if ! which setfattr > /dev/null 2>&1; then
  echo "Установка attr..."
  apk add --no-cache attr
fi

# Устанавливаем extended attributes для файла
set_attrs() {
  FILE=$1
  MIME_TYPE=$2
  CACHE_CONTROL=$3
  echo "Установка атрибутов для файла: $FILE"
  echo "  MIME-Type: $MIME_TYPE"
  echo "  Cache-Control: $CACHE_CONTROL"
  
  # Устанавливаем атрибуты
  setfattr -n user.supabase.content-type -v "$MIME_TYPE" "$FILE"
  setfattr -n user.supabase.cache-control -v "$CACHE_CONTROL" "$FILE"
}

# Получаем информацию о файлах из базы данных
echo "Получение информации о файлах из базы данных..."
QUERY="SELECT name, metadata->>'mimetype' as mimetype, metadata->>'cacheControl' as cache_control FROM storage.objects;"
DB_RESULTS=$(PGPASSWORD=$(echo $DB_PASSWORD) psql -U $(echo $DB_USER) -h $(echo $DB_HOST) -d $(echo $DB_NAME) -t -c "$QUERY")

# Обрабатываем результаты запроса
echo "$DB_RESULTS" | while read -r LINE; do
  # Извлекаем имя файла, MIME-тип и Cache-Control
  NAME=$(echo "$LINE" | awk -F'|' '{print $1}' | sed 's/^ *//;s/ *$//')
  MIME_TYPE=$(echo "$LINE" | awk -F'|' '{print $2}' | sed 's/^ *//;s/ *$//')
  CACHE_CONTROL=$(echo "$LINE" | awk -F'|' '{print $3}' | sed 's/^ *//;s/ *$//')
  
  # Если MIME-тип или Cache-Control пустые, устанавливаем значения по умолчанию
  [ -z "$MIME_TYPE" ] && MIME_TYPE="application/octet-stream"
  [ -z "$CACHE_CONTROL" ] && CACHE_CONTROL="max-age=3600"
  
  # Получаем информацию о bucket_id для файла
  BUCKET_QUERY="SELECT bucket_id FROM storage.objects WHERE name = '$NAME' LIMIT 1;"
  BUCKET_ID=$(PGPASSWORD=$(echo $DB_PASSWORD) psql -U $(echo $DB_USER) -h $(echo $DB_HOST) -d $(echo $DB_NAME) -t -c "$BUCKET_QUERY" | sed 's/^ *//;s/ *$//')
  
  # Если имя файла содержит путь, разбиваем его на компоненты
  if echo "$NAME" | grep -q "/"; then
    # Получаем первый компонент пути (может быть bucket_id или папка внутри bucket)
    FIRST_COMPONENT=$(echo "$NAME" | cut -d'/' -f1)
    # Получаем остальную часть пути
    REST_PATH=$(echo "$NAME" | cut -d'/' -f2-)
    
    # Проверяем, является ли первый компонент bucket_id
    if [ "$FIRST_COMPONENT" = "$BUCKET_ID" ]; then
      # Если первый компонент - это bucket_id, формируем путь
      DIR_PATH="/var/lib/storage/stub/stub/$BUCKET_ID/$REST_PATH"
    else
      # Если первый компонент - это не bucket_id, значит это папка внутри bucket
      # Формируем путь с учетом bucket_id из базы данных
      DIR_PATH="/var/lib/storage/stub/stub/$BUCKET_ID/$NAME"
    fi
  else
    # Если имя файла не содержит путь, формируем путь с учетом bucket_id из базы данных
    if [ -n "$BUCKET_ID" ]; then
      DIR_PATH="/var/lib/storage/stub/stub/$BUCKET_ID/$NAME"
    else
      # Если bucket_id не найден, пробуем найти файл в разных директориях
      echo "Не удалось определить bucket_id для файла: $NAME"
      
      # Проверяем все возможные bucket'ы
      DIR_FOUND=false
      
      # Проверяем каждый возможный bucket по отдельности
      for BUCKET in avatars certificates_img email-assets logos portfolio-images proposals leads messages; do
        POSSIBLE_PATH="/var/lib/storage/stub/stub/$BUCKET/$NAME"
        if [ -d "$POSSIBLE_PATH" ]; then
          DIR_PATH="$POSSIBLE_PATH"
          DIR_FOUND=true
          break
        fi
      done
      
      if [ "$DIR_FOUND" = false ]; then
        DIR_PATH=""
      fi
    fi
  fi
  
  # Проверяем, существует ли директория
  if [ -n "$DIR_PATH" ] && [ -d "$DIR_PATH" ]; then
    echo "Обработка директории: $DIR_PATH"
    
    # Обрабатываем каждый файл в директории
    find "$DIR_PATH" -maxdepth 1 -type f | while read FILE; do
      set_attrs "$FILE" "$MIME_TYPE" "$CACHE_CONTROL"
    done
  elif [ -n "$DIR_PATH" ]; then
    # Если директория не найдена, проверяем, может быть это файл в portfolio-images/partner-freelancers
    if echo "$NAME" | grep -q -v "/"; then
      # Для файлов без пути проверяем специальные случаи
      SPECIAL_PATH="/var/lib/storage/stub/stub/portfolio-images/partner-freelancers/$NAME"
      
      if [ -d "$SPECIAL_PATH" ]; then
        echo "Обработка специальной директории: $SPECIAL_PATH"
        find "$SPECIAL_PATH" -maxdepth 1 -type f | while read FILE; do
          set_attrs "$FILE" "$MIME_TYPE" "$CACHE_CONTROL"
        done
      fi
    else
      echo "Директория не найдена: $DIR_PATH"
    fi
  fi
done

echo "Готово!"
EOF

# Делаем скрипт исполняемым
chmod +x "$TEMP_SCRIPT"

# Копируем скрипт в под
echo "Копирование скрипта в под..."
kubectl cp "$TEMP_SCRIPT" "$NAMESPACE/$POD_NAME:/tmp/fix-attrs.sh"

# Выполняем скрипт в поде
echo "Выполнение скрипта в поде..."
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- sh /tmp/fix-attrs.sh

# Очистка
echo "Очистка..."
rm "$TEMP_SCRIPT"
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- rm /tmp/fix-attrs.sh

echo "=== Установка extended attributes завершена ==="