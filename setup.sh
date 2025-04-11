#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Default values
DEFAULT_STORAGE_CLASS="local-path"
DEFAULT_DB_USER="supabase_admin"
DEFAULT_PSQL_POOLER_PORT="65432"  # NodePort для доступа к PostgreSQL извне (должен быть в диапазоне 30000-32767)

echo "Starting Supabase setup..."

# Function to generate random alphanumeric string of specified length
generate_alphanumeric() {
  length=$1
  LC_ALL=C < /dev/urandom tr -dc 'a-zA-Z0-9' | head -c $length
}

# Function to generate a JWT token
generate_jwt() {
  role=$1
  secret=$2
  
  # Create a header
  header='{"alg":"HS256","typ":"JWT"}'
  header_base64=$(echo -n "$header" | base64 | tr -d '=' | tr '/+' '_-')
  
  # Create a payload with role, issuer, issued at, and expiry
  current_time=$(date +%s)
  expiry_time=$((current_time + 157680000)) # 5 years in seconds
  
  payload="{\"role\":\"$role\",\"iss\":\"supabase-kubernetes\",\"iat\":$current_time,\"exp\":$expiry_time}"
  payload_base64=$(echo -n "$payload" | base64 | tr -d '=' | tr '/+' '_-')
  
  # Create the signature
  signature=$(echo -n "${header_base64}.${payload_base64}" | openssl dgst -binary -sha256 -hmac "$secret" | base64 | tr -d '=' | tr '/+' '_-')
  
  # Return the complete JWT
  echo "${header_base64}.${payload_base64}.${signature}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --db-user)
      DB_USER="$2"
      shift 2
      ;;
    --anon-key)
      ANON_KEY="$2"
      shift 2
      ;;
    --service-key)
      SERVICE_KEY="$2"
      shift 2
      ;;
    --jwt-secret)
      JWT_SECRET="$2"
      shift 2
      ;;
    --postgres-password)
      POSTGRES_PASSWORD="$2"
      shift 2
      ;;
    --dashboard-username)
      DASHBOARD_USERNAME="$2"
      shift 2
      ;;
    --dashboard-password)
      DASHBOARD_PASSWORD="$2"
      shift 2
      ;;
    --google-client-id)
      GOOGLE_CLIENT_ID="$2"
      shift 2
      ;;
    --google-client-secret)
      GOOGLE_CLIENT_SECRET="$2"
      shift 2
      ;;
    --secret-key-base)
      SECRET_KEY_BASE="$2"
      shift 2
      ;;
    --vault-enc-key)
      VAULT_ENC_KEY="$2"
      shift 2
      ;;
    --supabase-public-url)
      SUPABASE_PUBLIC_URL="$2"
      shift 2
      ;;
    --site-url)
      SITE_URL="$2"
      shift 2
      ;;
    --api-external-url)
      API_EXTERNAL_URL="$2"
      shift 2
      ;;
    --google-project-id)
      GOOGLE_PROJECT_ID="$2"
      shift 2
      ;;
    --google-project-number)
      GOOGLE_PROJECT_NUMBER="$2"
      shift 2
      ;;
    --google-redirect-url)
      GOOGLE_REDIRECT_URL="$2"
      shift 2
      ;;
    --additional-redirect-urls)
      ADDITIONAL_REDIRECT_URLS="$2"
      shift 2
      ;;
    --smtp-pass)
      SMTP_PASS="$2"
      shift 2
      ;;
    --smtp-admin-email)
      SMTP_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --smtp-host)
      SMTP_HOST="$2"
      shift 2
      ;;
    --smtp-port)
      SMTP_PORT="$2"
      shift 2
      ;;
    --smtp-user)
      SMTP_USER="$2"
      shift 2
      ;;
    --smtp-sender-name)
      SMTP_SENDER_NAME="$2"
      shift 2
      ;;
    --voyage-api-key)
      VOYAGE_API_KEY="$2"
      shift 2
      ;;
    --openai-api-key)
      OPENAI_API_KEY="$2"
      shift 2
      ;;
    --extra-rest-schemas)
      EXTRA_REST_SCHEMAS="$2"
      shift 2
      ;;
    --psql-pooler-port)
      PSQL_POOLER_PORT="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --namespace NAME                  Kubernetes namespace to install Supabase"
      echo "  --domain DOMAIN                   Domain for Supabase"
      echo "  --db-user USERNAME                Database admin username (default: $DEFAULT_DB_USER)"
      echo "  --anon-key KEY                    Anon key for Supabase"
      echo "  --service-key KEY                 Service role key for Supabase"
      echo "  --jwt-secret SECRET               JWT secret for Supabase"
      echo "  --postgres-password PASSWORD      Postgres password"
      echo "  --dashboard-username USERNAME     Dashboard username"
      echo "  --dashboard-password PASSWORD     Dashboard password"
      echo "  --google-client-id ID             Google client ID for OAuth"
      echo "  --google-client-secret SECRET     Google client secret for OAuth"
      echo "  --secret-key-base KEY             Secret key base for Supabase"
      echo "  --vault-enc-key KEY               Vault encryption key"
      echo "  --supabase-public-url URL         Public URL for Supabase"
      echo "  --site-url URL                    Site URL"
      echo "  --api-external-url URL            External API URL"
      echo "  --google-project-id ID            Google project ID"
      echo "  --google-project-number NUMBER    Google project number"
      echo "  --google-redirect-url URL         Google redirect URL"
      echo "  --additional-redirect-urls URLS   Additional redirect URLs"
      echo "  --smtp-pass PASSWORD              SMTP password"
      echo "  --smtp-admin-email EMAIL          SMTP admin email"
      echo "  --smtp-host HOST                  SMTP host"
      echo "  --smtp-port PORT                  SMTP port"
      echo "  --smtp-user USER                  SMTP user"
      echo "  --smtp-sender-name NAME           SMTP sender name"
      echo "  --voyage-api-key KEY              Voyage API key"
      echo "  --openai-api-key KEY              OpenAI API key"
      echo "  --extra-rest-schemas SCHEMAS      Extra schemas for REST API (comma-separated)"
      echo "  --psql-pooler-port PORT           NodePort для внешнего доступа к PostgreSQL (default: $DEFAULT_PSQL_POOLER_PORT)"
      echo "  --help                            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Request namespace if not provided
if [ -z "$NAMESPACE" ]; then
  read -p "Enter namespace for Supabase installation: " NAMESPACE
  if [ -z "$NAMESPACE" ]; then
    echo "Namespace cannot be empty. Exiting."
    exit 1
  fi
fi

# Request domain if not provided
if [ -z "$DOMAIN" ]; then
  read -p "Enter domain for Supabase (e.g., supabase.example.com): " DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo "Domain cannot be empty. Exiting."
    exit 1
  fi
fi

# Set remaining values
STORAGE_CLASS=$DEFAULT_STORAGE_CLASS
DB_USER=${DB_USER:-$DEFAULT_DB_USER}
PSQL_POOLER_PORT=${PSQL_POOLER_PORT:-$DEFAULT_PSQL_POOLER_PORT}

echo "Using namespace: $NAMESPACE"
echo "Using domain: $DOMAIN"
echo "Using database user: $DB_USER"
echo "Using PostgreSQL pooler NodePort: $PSQL_POOLER_PORT"


# Check if namespace exists, if not create it
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
  echo "Creating namespace $NAMESPACE..."
  kubectl create namespace $NAMESPACE
else
  echo "Namespace $NAMESPACE already exists, will upgrade existing resources..."
fi

# Generate or use provided secrets
echo "Setting up secrets..."
JWT_SECRET=${JWT_SECRET:-$(generate_alphanumeric 32)}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(generate_alphanumeric 32)}
LOGFLARE_API_KEY=${LOGFLARE_API_KEY:-$(generate_alphanumeric 32)}
SMTP_PASSWORD=${SMTP_PASS:-$(generate_alphanumeric 32)}
SECRET_KEY_BASE=${SECRET_KEY_BASE:-$(generate_alphanumeric 32)}
VAULT_ENC_KEY=${VAULT_ENC_KEY:-$(generate_alphanumeric 32)}
VOYAGE_API_KEY=${VOYAGE_API_KEY:-""}
OPENAI_API_KEY=${OPENAI_API_KEY:-""}
DASHBOARD_USERNAME=${DASHBOARD_USERNAME:-"admin"}
DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD:-$(generate_alphanumeric 16)}

# Generate or use provided JWT tokens
echo "Setting up JWT tokens..."
ANON_KEY=${ANON_KEY:-$(generate_jwt "anon" "$JWT_SECRET")}
SERVICE_KEY=${SERVICE_KEY:-$(generate_jwt "service_role" "$JWT_SECRET")}

# Set up URLs
SUPABASE_PUBLIC_URL=${SUPABASE_PUBLIC_URL:-"https://$DOMAIN"}
SITE_URL=${SITE_URL:-"https://$DOMAIN"}
API_EXTERNAL_URL=${API_EXTERNAL_URL:-"https://$DOMAIN"}

# Prepare DB schemas for REST API
DEFAULT_DB_SCHEMAS="public,storage,graphql_public"
if [ -n "$EXTRA_REST_SCHEMAS" ]; then
  DB_SCHEMAS="$DEFAULT_DB_SCHEMAS,$EXTRA_REST_SCHEMAS"
else
  DB_SCHEMAS="${PGRST_DB_SCHEMAS:-$DEFAULT_DB_SCHEMAS}"
fi
# Install Supabase using Helm
echo "Installing Supabase using Helm..."
echo "NAMESPACE: $NAMESPACE"
echo "PWD: $(pwd)"

# Run Helm command with explicit chart path
cd "$(dirname "$0")"
echo "Current directory: $(pwd)"
echo "Running Helm command with values.yaml from process substitution"

# Run the Helm command with values from process substitution
helm upgrade --install supabase charts/supabase -n $NAMESPACE -f <(cat << EOF
Domain: $DOMAIN
db:
  image:
    tag: 15.8.1.020
  persistence:
    storageClassName: local-path
    size: 200Gi
studio:
  image:
    tag: 20250113-83c9420
  environment:
    SUPABASE_PUBLIC_URL: $SUPABASE_PUBLIC_URL
    STUDIO_DEFAULT_ORGANIZATION: ${STUDIO_DEFAULT_ORGANIZATION:-Default Organization}
    STUDIO_DEFAULT_PROJECT: ${STUDIO_DEFAULT_PROJECT:-Default Project}
    OPENAI_API_KEY: ${OPENAI_API_KEY:-}
    NEXT_ANALYTICS_BACKEND_PROVIDER: ${GOOGLE_PROJECT_ID:+bigquery}${GOOGLE_PROJECT_ID:-postgres}
auth:
  image:
    tag: v2.167.0
  environment:
    API_EXTERNAL_URL: $API_EXTERNAL_URL
    GOTRUE_SITE_URL: $SITE_URL
    GOTRUE_URI_ALLOW_LIST: ${ADDITIONAL_REDIRECT_URLS:-*}
    GOTRUE_DISABLE_SIGNUP: ${DISABLE_SIGNUP:-false}
    GOTRUE_EXTERNAL_EMAIL_ENABLED: ${ENABLE_EMAIL_SIGNUP:-true}
    GOTRUE_MAILER_AUTOCONFIRM: ${ENABLE_EMAIL_AUTOCONFIRM:-true}
    GOTRUE_EXTERNAL_PHONE_ENABLED: ${ENABLE_PHONE_SIGNUP:-false}
    GOTRUE_SMS_AUTOCONFIRM: ${ENABLE_PHONE_AUTOCONFIRM:-false}
    GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED: ${ENABLE_ANONYMOUS_USERS:-false}
    GOTRUE_EXTERNAL_GOOGLE_ENABLED: ${GOOGLE_CLIENT_ID:+true}
    GOTRUE_EXTERNAL_GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
    GOTRUE_EXTERNAL_GOOGLE_SECRET: ${GOOGLE_CLIENT_SECRET:-}
    GOTRUE_EXTERNAL_GOOGLE_REDIRECT_URI: ${GOOGLE_REDIRECT_URL:-}
    GOTRUE_SMTP_HOST: ${SMTP_HOST:-}
    GOTRUE_SMTP_PORT: ${SMTP_PORT:-}
    GOTRUE_SMTP_USER: ${SMTP_USER:-}
    GOTRUE_SMTP_PASS: ${SMTP_PASS:-}
    GOTRUE_SMTP_ADMIN_EMAIL: ${SMTP_ADMIN_EMAIL:-${SMTP_USER:-}}
    GOTRUE_SMTP_SENDER_NAME: ${SMTP_SENDER_NAME:-Supabase}
    GOTRUE_MAILER_URLPATHS_INVITE: ${MAILER_URLPATHS_INVITE:-/auth/v1/verify}
    GOTRUE_MAILER_URLPATHS_CONFIRMATION: ${MAILER_URLPATHS_CONFIRMATION:-/auth/v1/verify}
    GOTRUE_MAILER_URLPATHS_RECOVERY: ${MAILER_URLPATHS_RECOVERY:-/auth/v1/verify}
    GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE: ${MAILER_URLPATHS_EMAIL_CHANGE:-/auth/v1/verify}
    GOTRUE_MAILER_TEMPLATES_INVITE: ${MAILER_TEMPLATES_INVITE:-http://supabase-nginx-templates/invite.html}
    GOTRUE_MAILER_TEMPLATES_CONFIRMATION: ${MAILER_TEMPLATES_CONFIRMATION:-http://supabase-nginx-templates/confirmation.html}
    GOTRUE_MAILER_TEMPLATES_RECOVERY: ${MAILER_TEMPLATES_RECOVERY:-http://supabase-nginx-templates/recovery.html}
    GOTRUE_MAILER_TEMPLATES_EMAIL_CHANGE: ${MAILER_TEMPLATES_EMAIL_CHANGE:-http://supabase-nginx-templates/email-change.html}
    GOTRUE_MAILER_TEMPLATES_MAGIC_LINK: ${MAILER_TEMPLATES_MAGIC_LINK:-http://supabase-nginx-templates/magic-link.html}
    DB_USER: $DB_USER
rest:
  image:
    tag: v12.2.0
  environment:
    PGRST_DB_SCHEMAS: $DB_SCHEMAS
    PGRST_JWT_EXP: ${JWT_EXPIRY:-3600}
    DB_USER: $DB_USER
realtime:
  image:
    tag: v2.34.7
  environment:
    APP_NAME: realtime
    SECRET_KEY_BASE: $SECRET_KEY_BASE
    DB_USER: $DB_USER
meta:
  image:
    tag: v0.84.2
  environment:
    DB_USER: $DB_USER
storage:
  image:
    tag: v1.14.5
  environment:
    ENABLE_IMAGE_TRANSFORMATION: ${ENABLE_IMAGE_TRANSFORMATION:-true}
    FILE_SIZE_LIMIT: ${FILE_SIZE_LIMIT:-52428800}
    DB_USER: $DB_USER
  persistence:
    enabled: true
    storageClassName: seaweedfs-storage
    size: 100Gi
    accessModes:
      - ReadWriteMany
imgproxy:
  image:
    tag: v3.8.0
  environment:
    IMGPROXY_ENABLE_WEBP_DETECTION: ${IMGPROXY_ENABLE_WEBP_DETECTION:-true}
kong:
  image:
    tag: 2.8.1
  ingress:
    enabled: false
  fullnameOverride: supabase-kong
analytics:
  image:
    tag: 1.4.0
  environment:
    DB_USERNAME: $DB_USER
vector:
  image:
    tag: 0.28.1-alpine
functions:
  image:
    tag: v1.66.5
  environment:
    VERIFY_JWT: ${FUNCTIONS_VERIFY_JWT:-true}
    VOYAGE_API_KEY: ${VOYAGE_API_KEY:-}
    VOYAGE_MODEL: ${VOYAGE_MODEL:-voyage-3}
    OPENAI_API_KEY: ${OPENAI_API_KEY:-}
supavisor:
  image:
    tag: 1.1.56
  secretKeyBase: $SECRET_KEY_BASE
  vaultEncKey: $VAULT_ENC_KEY
  tenantId: ${POOLER_TENANT_ID:-default}
  defaultPoolSize: ${POOLER_DEFAULT_POOL_SIZE:-20}
  maxClientConn: ${POOLER_MAX_CLIENT_CONN:-100}
  port: 6543  # Внутренний порт Supavisor
  service:
    type: NodePort
    nodePort: $PSQL_POOLER_PORT
secret:
  jwt:
    anonKey: $ANON_KEY
    serviceKey: $SERVICE_KEY
    secret: $JWT_SECRET
  db:
    username: $DB_USER
    password: $POSTGRES_PASSWORD
    database: postgres
  analytics:
    apiKey: $LOGFLARE_API_KEY
  smtp:
    username: admin
    password: $SMTP_PASSWORD
  dashboard:
    username: $DASHBOARD_USERNAME
    password: $DASHBOARD_PASSWORD
EOF
)

echo "Waiting for pods to start..."
sleep 10

# Check pod status
kubectl get pods -n $NAMESPACE

echo -e "${GREEN}Supabase installation complete!${NC}"
echo "You can check the status of the pods with:"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "Creating IngressRoute for Traefik..."
# Extract hostname from SUPABASE_PUBLIC_URL if provided, otherwise use DOMAIN
if [ -n "$SUPABASE_PUBLIC_URL" ]; then
  INGRESS_HOST=$(echo "$SUPABASE_PUBLIC_URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
else
  INGRESS_HOST="$DOMAIN"
fi

kubectl apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: supabase
  namespace: $NAMESPACE
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`$INGRESS_HOST\`)
      kind: Rule
      services:
        - name: supabase-kong
          port: 8000
  tls:
    certResolver: letsencrypt
EOF
echo ""
echo "You can also access the Supabase Studio via port forwarding:"
echo "kubectl port-forward svc/supabase-kong 8000:8000 -n $NAMESPACE"
echo ""
echo "Then visit: http://localhost:8000"
echo ""
echo "For PostgreSQL connection pooling via NodePort:"
echo "Connect to: postgresql://$DB_USER:$POSTGRES_PASSWORD@<node-ip>:$PSQL_POOLER_PORT/postgres"
echo ""
echo "Where <node-ip> is the IP-адрес любой ноды вашего кластера Kubernetes"
echo ""
echo -e "${GREEN}=== Credentials and API Keys ===${NC}"
echo -e "Dashboard credentials:"
echo -e "  Username: ${GREEN}$DASHBOARD_USERNAME${NC}"
echo -e "  Password: ${GREEN}$DASHBOARD_PASSWORD${NC}"
echo -e ""
echo -e "Database credentials:"
echo -e "  Username: ${GREEN}$DB_USER${NC}"
echo -e "  Password: ${GREEN}$POSTGRES_PASSWORD${NC}"
echo -e ""
echo -e "API Keys:"
echo -e "  ANON_KEY: ${GREEN}$ANON_KEY${NC}"
echo -e "  SERVICE_KEY: ${GREEN}$SERVICE_KEY${NC}"
echo -e ""
echo -e "Other secrets:"
echo -e "  JWT_SECRET: ${GREEN}$JWT_SECRET${NC}"
echo -e "  LOGFLARE_API_KEY: ${GREEN}$LOGFLARE_API_KEY${NC}"
echo -e "  SMTP_PASSWORD: ${GREEN}$SMTP_PASSWORD${NC}"
echo -e "  SECRET_KEY_BASE: ${GREEN}$SECRET_KEY_BASE${NC}"
