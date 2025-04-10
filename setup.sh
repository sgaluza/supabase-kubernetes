#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Default values
DEFAULT_STORAGE_CLASS="local-path"
DEFAULT_DB_USER="supabase_admin"

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
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --namespace NAME      Kubernetes namespace to install Supabase"
      echo "  --domain DOMAIN       Domain for Supabase"
      echo "  --db-user USERNAME    Database admin username (default: $DEFAULT_DB_USER)"
      echo "  --help                Show this help message"
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

echo "Using namespace: $NAMESPACE"
echo "Using domain: $DOMAIN"
echo "Using database user: $DB_USER"

# Check if namespace exists, if not create it
if ! kubectl --kubeconfig ~/.kube/atrvd-config get namespace $NAMESPACE &> /dev/null; then
  echo "Creating namespace $NAMESPACE..."
  kubectl --kubeconfig ~/.kube/atrvd-config create namespace $NAMESPACE
else
  echo "Namespace $NAMESPACE already exists, cleaning up..."
  # Delete any existing resources in the namespace
  kubectl --kubeconfig ~/.kube/atrvd-config delete --all deployments,services,pods,pvc,configmaps,secrets,statefulsets -n $NAMESPACE --ignore-not-found
  
  # Find and delete any PVs that might be related to this namespace
  echo "Looking for orphaned PVs..."
  PVS=$(kubectl --kubeconfig ~/.kube/atrvd-config get pv -o json | jq -r '.items[] | select(.spec.claimRef.namespace == "'$NAMESPACE'") | .metadata.name')
  if [ -n "$PVS" ]; then
    echo "Found orphaned PVs, deleting..."
    for PV in $PVS; do
      kubectl --kubeconfig ~/.kube/atrvd-config delete pv $PV --force
    done
  fi
fi

# Generate secrets
echo "Generating secrets..."
JWT_SECRET=$(generate_alphanumeric 32)
POSTGRES_PASSWORD=$(generate_alphanumeric 32)
LOGFLARE_API_KEY=$(generate_alphanumeric 32)
SMTP_PASSWORD=$(generate_alphanumeric 32)
SECRET_KEY_BASE=$(generate_alphanumeric 32)
VAULT_ENC_KEY=$(generate_alphanumeric 32)
DASHBOARD_USERNAME="admin"
DASHBOARD_PASSWORD=$(generate_alphanumeric 16)

# Generate JWT tokens
echo "Generating JWT tokens..."
ANON_KEY=$(generate_jwt "anon" "$JWT_SECRET")
SERVICE_KEY=$(generate_jwt "service_role" "$JWT_SECRET")

# Generate JWT tokens without printing them yet

# Prepare Helm set parameters
HELM_PARAMS=""
HELM_PARAMS="$HELM_PARAMS --set Domain=$DOMAIN"

# Set correct image tags
HELM_PARAMS="$HELM_PARAMS --set db.image.tag=15.8.1.020"
HELM_PARAMS="$HELM_PARAMS --set studio.image.tag=20250113-83c9420"
HELM_PARAMS="$HELM_PARAMS --set auth.image.tag=v2.167.0"
HELM_PARAMS="$HELM_PARAMS --set rest.image.tag=v12.2.0"
HELM_PARAMS="$HELM_PARAMS --set realtime.image.tag=v2.34.7"
HELM_PARAMS="$HELM_PARAMS --set meta.image.tag=v0.84.2"
HELM_PARAMS="$HELM_PARAMS --set storage.image.tag=v1.14.5"
HELM_PARAMS="$HELM_PARAMS --set imgproxy.image.tag=v3.8.0"
HELM_PARAMS="$HELM_PARAMS --set kong.image.tag=2.8.1"
HELM_PARAMS="$HELM_PARAMS --set analytics.image.tag=1.4.0"
HELM_PARAMS="$HELM_PARAMS --set vector.image.tag=0.28.1-alpine"
HELM_PARAMS="$HELM_PARAMS --set functions.image.tag=v1.66.5"

# Set the secrets directly in Helm
HELM_PARAMS="$HELM_PARAMS --set secret.jwt.anonKey=$ANON_KEY"
HELM_PARAMS="$HELM_PARAMS --set secret.jwt.serviceKey=$SERVICE_KEY"
HELM_PARAMS="$HELM_PARAMS --set secret.jwt.secret=$JWT_SECRET"

HELM_PARAMS="$HELM_PARAMS --set secret.db.username=$DB_USER"
HELM_PARAMS="$HELM_PARAMS --set secret.db.password=$POSTGRES_PASSWORD"
HELM_PARAMS="$HELM_PARAMS --set secret.db.database=postgres"

HELM_PARAMS="$HELM_PARAMS --set secret.analytics.apiKey=$LOGFLARE_API_KEY"

HELM_PARAMS="$HELM_PARAMS --set secret.smtp.username=admin"
HELM_PARAMS="$HELM_PARAMS --set secret.smtp.password=$SMTP_PASSWORD"

HELM_PARAMS="$HELM_PARAMS --set secret.dashboard.username=$DASHBOARD_USERNAME"
HELM_PARAMS="$HELM_PARAMS --set secret.dashboard.password=$DASHBOARD_PASSWORD"

# Storage configuration
HELM_PARAMS="$HELM_PARAMS --set db.persistence.storageClassName=$STORAGE_CLASS"
HELM_PARAMS="$HELM_PARAMS --set storage.persistence.storageClassName=$STORAGE_CLASS"
HELM_PARAMS="$HELM_PARAMS --set imgproxy.persistence.storageClassName=$STORAGE_CLASS"

# Supavisor configuration
HELM_PARAMS="$HELM_PARAMS --set supavisor.image.tag=1.1.56"
HELM_PARAMS="$HELM_PARAMS --set supavisor.secretKeyBase=$SECRET_KEY_BASE"
HELM_PARAMS="$HELM_PARAMS --set supavisor.vaultEncKey=$VAULT_ENC_KEY"
HELM_PARAMS="$HELM_PARAMS --set supavisor.tenantId=default"

# Studio configuration
HELM_PARAMS="$HELM_PARAMS --set studio.environment.SUPABASE_PUBLIC_URL=https://$DOMAIN"

# Disable Ingress creation, as we'll use Traefik's custom IngressRoute
HELM_PARAMS="$HELM_PARAMS --set kong.ingress.enabled=false"
HELM_PARAMS="$HELM_PARAMS --set kong.fullnameOverride=supabase-kong"

# Auth service configuration
HELM_PARAMS="$HELM_PARAMS --set auth.environment.API_EXTERNAL_URL=https://$DOMAIN"
HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_SITE_URL=https://$DOMAIN"
HELM_PARAMS="$HELM_PARAMS --set auth.environment.GOTRUE_SMTP_PORT=587"

# Realtime service configuration
HELM_PARAMS="$HELM_PARAMS --set realtime.environment.APP_NAME=realtime"
HELM_PARAMS="$HELM_PARAMS --set realtime.environment.SECRET_KEY_BASE=$SECRET_KEY_BASE"

# We don't need to set POSTGRES_USER as it's already defined in the template
# and will be taken from secret.db.username

# Set the DB credentials for all services
# We only need to set the DB_USER/DB_USERNAME, as DB_PASSWORD is already defined in the templates
# and will be taken from secret.db.password
for service in analytics meta realtime storage auth rest; do
  # Use DB_USER or DB_USERNAME depending on the service
  if [ "$service" = "analytics" ]; then
    HELM_PARAMS="$HELM_PARAMS --set $service.environment.DB_USERNAME=$DB_USER"
  else
    HELM_PARAMS="$HELM_PARAMS --set $service.environment.DB_USER=$DB_USER"
  fi
done
# Install Supabase using Helm with parameters
echo "Installing Supabase using Helm..."
helm upgrade --install supabase charts/supabase -n $NAMESPACE $HELM_PARAMS --kubeconfig ~/.kube/atrvd-config

echo "Waiting for pods to start..."
sleep 10

# Check pod status
kubectl --kubeconfig ~/.kube/atrvd-config get pods -n $NAMESPACE

echo -e "${GREEN}Supabase installation complete!${NC}"
echo "You can check the status of the pods with:"
echo "kubectl get pods -n $NAMESPACE"
echo ""
echo "Creating IngressRoute for Traefik..."
kubectl --kubeconfig ~/.kube/atrvd-config apply -f - <<EOF
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: supabase
  namespace: $NAMESPACE
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`$DOMAIN\`)
      kind: Rule
      services:
        - name: supabase-kong
          port: 8000
  tls:
    certResolver: letsencrypt
EOF
echo ""
echo "You can also access the Supabase Studio via port forwarding:"
echo "kubectl --kubeconfig ~/.kube/atrvd-config port-forward svc/supabase-kong 8000:8000 -n $NAMESPACE"
echo ""
echo "Then visit: http://localhost:8000"
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
