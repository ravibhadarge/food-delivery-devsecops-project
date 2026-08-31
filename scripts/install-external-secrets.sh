#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# install-external-secrets.sh
# Installs External Secrets Operator on EKS
# Syncs secrets from AWS Secrets Manager → Kubernetes Secrets
# 
# Usage: bash install-external-secrets.sh
# ═══════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

NAMESPACE="food-delivery"
ESO_NAMESPACE="external-secrets"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-food-delivery-cluster}"

echo "=========================================="
echo "  EXTERNAL SECRETS OPERATOR — Setup"
echo "=========================================="
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Install External Secrets Operator via Helm
# ─────────────────────────────────────────────────────────────────
info "Installing External Secrets Operator..."

helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace ${ESO_NAMESPACE} \
  --create-namespace \
  --set installCRDs=true \
  --wait

info "External Secrets Operator installed ✅"

# ─────────────────────────────────────────────────────────────────
# Step 2: Create IRSA (IAM Role for Service Account)
# ─────────────────────────────────────────────────────────────────
info "Creating IAM Service Account for External Secrets..."

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get OIDC Provider
OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

info "Account: ${AWS_ACCOUNT_ID}"
info "OIDC: ${OIDC_PROVIDER}"

# Create IAM policy for Secrets Manager access
cat > /tmp/eso-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${AWS_ACCOUNT_ID}:secret:food-delivery/*"
    }
  ]
}
EOF

# Create or update policy
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/food-delivery-eso-policy"
aws iam create-policy \
  --policy-name food-delivery-eso-policy \
  --policy-document file:///tmp/eso-policy.json 2>/dev/null || \
aws iam create-policy-version \
  --policy-arn ${POLICY_ARN} \
  --policy-document file:///tmp/eso-policy.json \
  --set-as-default 2>/dev/null || true

# Create trust policy for IRSA
cat > /tmp/eso-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:food-delivery-eso-sa",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

# Create or update role
ROLE_NAME="food-delivery-eso-role"
aws iam create-role \
  --role-name ${ROLE_NAME} \
  --assume-role-policy-document file:///tmp/eso-trust.json 2>/dev/null || \
aws iam update-assume-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-document file:///tmp/eso-trust.json

aws iam attach-role-policy \
  --role-name ${ROLE_NAME} \
  --policy-arn ${POLICY_ARN} 2>/dev/null || true

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
info "IAM Role: ${ROLE_ARN}"

# ─────────────────────────────────────────────────────────────────
# Step 3: Create Kubernetes Service Account with IRSA annotation
# ─────────────────────────────────────────────────────────────────
info "Creating Kubernetes Service Account..."

kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: food-delivery-eso-sa
  namespace: ${NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${ROLE_ARN}
EOF

# ─────────────────────────────────────────────────────────────────
# Step 4: Create SecretStore (connects to AWS Secrets Manager)
# ─────────────────────────────────────────────────────────────────
info "Creating SecretStore..."

cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: ${NAMESPACE}
spec:
  provider:
    aws:
      service: SecretsManager
      region: ${AWS_REGION}
      auth:
        jwt:
          serviceAccountRef:
            name: food-delivery-eso-sa
EOF

# ─────────────────────────────────────────────────────────────────
# Step 5: Create ExternalSecret (syncs AWS → K8s)
# ─────────────────────────────────────────────────────────────────
info "Creating ExternalSecret (syncs AWS Secrets Manager → K8s)..."

cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: food-delivery-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: food-delivery-secrets
    creationPolicy: Owner
  data:
    - secretKey: mongodb-uri
      remoteRef:
        key: food-delivery/app-secrets
        property: MONGODB_URI
    - secretKey: jwt-secret
      remoteRef:
        key: food-delivery/app-secrets
        property: JWT_SECRET
    - secretKey: stripe-secret-key
      remoteRef:
        key: food-delivery/app-secrets
        property: STRIPE_SECRET_KEY
EOF

# ─────────────────────────────────────────────────────────────────
# Verify
# ─────────────────────────────────────────────────────────────────
info "Waiting for secret sync..."
sleep 10

echo ""
info "Checking ExternalSecret status:"
kubectl get externalsecret -n ${NAMESPACE}
echo ""
info "Checking synced Kubernetes secret:"
kubectl get secret food-delivery-secrets -n ${NAMESPACE}

echo ""
echo "=========================================="
echo "  ✅ EXTERNAL SECRETS SETUP COMPLETE!"
echo "=========================================="
echo ""
info "Secrets are now auto-synced from AWS Secrets Manager every 1 hour."
info "To force refresh: kubectl annotate externalsecret food-delivery-secrets -n ${NAMESPACE} force-sync=\$(date +%s) --overwrite"
echo ""
info "Update secrets in AWS Secrets Manager:"
echo "  aws secretsmanager put-secret-value \\"
echo "    --secret-id food-delivery/app-secrets \\"
echo "    --secret-string '{\"MONGODB_URI\":\"your-uri\",\"JWT_SECRET\":\"your-secret\",\"STRIPE_SECRET_KEY\":\"your-stripe-key\"}'"
echo ""
