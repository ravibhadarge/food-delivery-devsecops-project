# AWS Secrets Manager — Keys Guide

This project uses **4 secrets** in AWS Secrets Manager. Below is exactly what keys you need, where to get them, and how to add them.

---

## Secret 1: `food-delivery/app-secrets`

**Purpose:** Application secrets used by the backend pods in Kubernetes.

| Key | What It Is | Where To Get It |
|-----|-----------|-----------------|
| `MONGODB_URI` | MongoDB connection string | MongoDB runs **inside Kubernetes cluster** — use: `mongodb://mongodb.food-delivery.svc.cluster.local:27017/food-delivery` |
| `JWT_SECRET` | Secret key for signing JWT tokens | Create any random strong string (minimum 32 characters). Example: `mySuperSecret123!@#FoodDelivery2024` |
| `STRIPE_SECRET_KEY` | Stripe payment secret key | Go to [Stripe Dashboard](https://dashboard.stripe.com/apikeys) → Copy the **Secret key** |

**How to add:**
```bash
aws secretsmanager update-secret \
  --secret-id food-delivery/app-secrets \
  --region us-east-1 \
  --secret-string '{
    "MONGODB_URI": "mongodb://mongodb.food-delivery.svc.cluster.local:27017/food-delivery",
    "JWT_SECRET": "your-random-strong-secret-minimum-32-characters",
    "STRIPE_SECRET_KEY": "your-stripe-secret-key-from-dashboard"
  }'
```

---

## Secret 2: `food-delivery/pipeline`

**Purpose:** CI/CD pipeline secrets used by GitHub Actions to run SonarQube analysis.

| Key | What It Is | Where To Get It |
|-----|-----------|-----------------|
| `SONAR_TOKEN` | SonarQube authentication token | Login to SonarQube (`http://<BASTION_IP>:9000`) → Click your profile icon (top-right) → **My Account** → **Security** → **Generate Tokens** → Give it a name → Copy the token (starts with `squ_`) |
| `SONAR_HOST_URL` | SonarQube server URL | `http://<BASTION_PUBLIC_IP>:9000` (get bastion IP from AWS Console → EC2 → find `food-delivery-bastion` → copy Public IPv4) |

**How to add:**
```bash
BASTION_IP=$(aws ec2 describe-instances --region us-east-1 \
  --filters "Name=tag:Name,Values=food-delivery-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

aws secretsmanager update-secret \
  --secret-id food-delivery/pipeline \
  --region us-east-1 \
  --secret-string "{
    \"SONAR_TOKEN\": \"squ_your_token_here\",
    \"SONAR_HOST_URL\": \"http://${BASTION_IP}:9000\"
  }"
```

---

## Secret 3: `food-delivery/database`

**Purpose:** Database credentials (for production MongoDB Atlas or AWS DocumentDB).

| Key | What It Is | Where To Get It |
|-----|-----------|-----------------|
| `DB_HOST` | Database hostname | MongoDB Atlas → Cluster → Connect → Copy hostname (e.g., `cluster0.xxxxx.mongodb.net`) |
| `DB_USERNAME` | Database username | The username you created in MongoDB Atlas → Database Access |
| `DB_PASSWORD` | Database password | The password you set for that user |
| `DB_NAME` | Database name | `food-delivery` (this is the database name used by the app) |
| `DB_PORT` | Database port | `27017` (default MongoDB port) |

**How to add:**
```bash
aws secretsmanager update-secret \
  --secret-id food-delivery/database \
  --region us-east-1 \
  --secret-string '{
    "DB_HOST": "cluster0.xxxxx.mongodb.net",
    "DB_USERNAME": "your-db-username",
    "DB_PASSWORD": "your-db-password",
    "DB_NAME": "food-delivery",
    "DB_PORT": "27017"
  }'
```

---

## Secret 4: `food-delivery/sonarqube`

**Purpose:** SonarQube credentials (same as pipeline but kept separate for bastion access).

| Key | What It Is | Where To Get It |
|-----|-----------|-----------------|
| `SONAR_TOKEN` | Same as Secret 2 | Same token from SonarQube |
| `SONAR_HOST_URL` | Same as Secret 2 | Same URL |

**How to add:**
```bash
aws secretsmanager update-secret \
  --secret-id food-delivery/sonarqube \
  --region us-east-1 \
  --secret-string "{
    \"SONAR_TOKEN\": \"squ_your_token_here\",
    \"SONAR_HOST_URL\": \"http://${BASTION_IP}:9000\"
  }"
```

---

## Quick Summary

| Secret ID | Keys Inside | Used By |
|-----------|-------------|---------|
| `food-delivery/app-secrets` | MONGODB_URI, JWT_SECRET, STRIPE_SECRET_KEY | Backend pods (via External Secrets Operator) |
| `food-delivery/pipeline` | SONAR_TOKEN, SONAR_HOST_URL | GitHub Actions pipeline (Stage 2: SonarQube) |
| `food-delivery/database` | DB_HOST, DB_USERNAME, DB_PASSWORD, DB_NAME, DB_PORT | Production database config |
| `food-delivery/sonarqube` | SONAR_TOKEN, SONAR_HOST_URL | Bastion server access |

---

## How Secrets Flow

```
AWS Secrets Manager
       │
       ├──→ GitHub Actions (reads pipeline secrets via OIDC)
       │         └── Uses SONAR_TOKEN for code analysis
       │
       └──→ External Secrets Operator (runs in EKS)
                 └── Syncs app-secrets → Kubernetes Secret
                         └── Backend pods read MONGODB_URI, JWT_SECRET, STRIPE_SECRET_KEY
```

---

## Important Notes

1. **Secrets are created automatically** by Terraform with placeholder values (`CHANGE_ME`). You only need to **update** them with real values.
2. **Never put real secrets in code** — always use `aws secretsmanager update-secret` command.
3. **External Secrets Operator** syncs every 1 hour. To force immediate sync:
   ```bash
   kubectl annotate externalsecret food-delivery-secrets -n food-delivery force-sync=$(date +%s) --overwrite
   ```
4. **To verify secrets are synced:**
   ```bash
   kubectl get externalsecret -n food-delivery
   kubectl get secret food-delivery-secrets -n food-delivery -o yaml
   ```
