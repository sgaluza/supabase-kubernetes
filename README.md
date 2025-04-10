# Supabase Kubernetes

Этот репозиторий содержит Helm-чарты и скрипты для развертывания Supabase в Kubernetes.

## Предварительные требования

- Кластер Kubernetes
- kubectl, настроенный для доступа к вашему кластеру
- Установленный Helm 3
- OpenSSL для генерации JWT-токенов
- Traefik Ingress Controller с настроенным Let's Encrypt для SSL-сертификатов

## Быстрый старт

Для развертывания Supabase в вашем кластере Kubernetes просто выполните:

```bash
./setup.sh --namespace <namespace> --domain <domain> --db-user <username>
```

Например:

```bash
./setup.sh --namespace demo1 --domain demo1.domain.com
```

Скрипт выполнит следующие действия:
1. Создаст или очистит указанное пространство имен
2. Сгенерирует необходимые секреты и JWT-токены
3. Установит Helm-чарт Supabase с соответствующими параметрами
4. Создаст IngressRoute для Traefik с поддержкой SSL через Let's Encrypt
5. Выведет все учетные данные и API-ключи

## Доступ к Supabase

После установки вы можете получить доступ к Supabase Studio через:

1. Домен, указанный при установке (например, https://demo1.domain.com)

2. Или через port-forwarding:

```bash
kubectl port-forward svc/supabase-kong 8000:8000 -n <namespace>
```

Затем посетите: http://localhost:8000

## Конфигурация

Скрипт установки генерирует случайные пароли, секреты и JWT-токены для безопасности. Если вам нужно настроить развертывание, вы можете изменить скрипт `setup.sh`, чтобы добавить или изменить параметры Helm, передаваемые с флагами `--set`.

## Мультитенантность и адаптация

Чарт был модифицирован для поддержки мультитенантности и адаптирован под современные Kubernetes-решения:

### Мультитенантность
- Vector использует Role и RoleBinding вместо ClusterRole и ClusterRoleBinding
- Каждый экземпляр Supabase устанавливается в отдельное пространство имен
- Для каждого экземпляра создается отдельный IngressRoute с уникальным доменом

### Хранилище
- По умолчанию используется Local Path Provisioner для хранения данных
- Все постоянные тома (PersistentVolumes) используют StorageClass "local-path"
- Можно настроить другой StorageClass при необходимости

### Ingress
- Вместо стандартного Kubernetes Ingress используется Traefik IngressRoute
- Автоматическая настройка SSL с Let's Encrypt через Traefik
- Поддержка DNS-вызова для выпуска сертификатов

### Кастомные Email шаблоны
- Добавлен nginx-сервер для хранения и обслуживания кастомных email шаблонов
- Шаблоны хранятся в PersistentVolume с использованием StorageClass "seaweedfs-storage"
- Легко интегрируется с Auth сервисом для использования кастомных шаблонов писем
- Доступ к шаблонам через URL: http://supabase-nginx-templates.namespace.svc.cluster.local/

## Компоненты

Развертывание Supabase включает следующие компоненты:

- PostgreSQL Database
- Supabase Studio (Admin UI)
- Auth Service (GoTrue)
- REST API (PostgREST)
- Realtime Service
- Storage API
- Functions
- Analytics
- Vector
- Kong API Gateway
- Image Proxy
- Nginx Templates (для кастомных email шаблонов)
- Supavisor (пул соединений для PostgreSQL)

## Устранение неполадок

Если у вас возникли проблемы с развертыванием, проверьте статус подов:

```bash
kubectl get pods -n <namespace>
```

И проверьте логи конкретных подов:

```bash
kubectl logs -n <namespace> <pod-name>
```

Для проверки IngressRoute:

```bash
kubectl get ingressroute -n <namespace>
```

Для проверки сервисов:

```bash
kubectl get svc -n <namespace>
```

## Использование кастомных email шаблонов

Для использования кастомных email шаблонов:

1. Загрузите шаблоны в PersistentVolume:
   ```bash
   kubectl cp your-templates/ <namespace>/supabase-nginx-templates-xxx:/usr/share/nginx/html/
   ```

2. Настройте Auth сервис для использования этих шаблонов, добавив в `setup.sh`:
   ```bash
   HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_MAILER_TEMPLATES_INVITE=http://supabase-nginx-templates/invite.html"
   HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_MAILER_TEMPLATES_CONFIRMATION=http://supabase-nginx-templates/confirmation.html"
   HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_MAILER_TEMPLATES_RECOVERY=http://supabase-nginx-templates/recovery.html"
   HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE=http://supabase-nginx-templates/email_change.html"
   HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_MAILER_TEMPLATES_MAGIC_LINK=http://supabase-nginx-templates/magic_link.html"
   ```

3. Проверьте доступность шаблонов:
   ```bash
   kubectl port-forward svc/supabase-nginx-templates 8080:80 -n <namespace>
   curl http://localhost:8080/invite.html
   ```

## Доступ к базе данных PostgreSQL

Для прямого доступа к базе данных PostgreSQL вы можете использовать Supavisor (пул соединений):

1. Доступ через стандартный порт PostgreSQL (5432):
   ```bash
   kubectl port-forward svc/supabase-supavisor 5432:5432 -n <namespace>
   ```

2. Доступ через порт пула соединений в транзакционном режиме (6543):
   ```bash
   kubectl port-forward svc/supabase-supavisor 6543:6543 -n <namespace>
   ```

3. Подключение к базе данных с помощью клиента PostgreSQL:
   ```bash
   # Через стандартный порт
   psql -h localhost -p 5432 -U supabase_admin -d postgres
   
   # Через порт пула соединений
   psql -h localhost -p 6543 -U supabase_admin -d postgres
   ```

Supavisor обеспечивает эффективное управление соединениями к базе данных, что особенно полезно при большом количестве одновременных подключений.
