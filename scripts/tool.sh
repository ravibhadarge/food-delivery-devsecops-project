#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# tool.sh — Bastion Server Setup Script
# Installs: kubectl, eksctl, Helm, AWS CLI, Docker, SonarQube
# Run as root: sudo bash tool.sh
# ═══════════════════════════════════════════════════════════════════

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

is_container_running() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -q "true"
}

print_container_logs() {
  echo "--- Container logs ($1) ---"
  docker logs "$1" 2>&1 | tail -20
  echo "---"
}

echo "=========================================="
echo "  BASTION SERVER SETUP — Food Delivery"
echo "=========================================="

# ─────────────────────────────────────────────────────────────────
# Update system
# ─────────────────────────────────────────────────────────────────
info "Updating system packages..."
yum update -y
yum install -y unzip git

if ! command -v curl >/dev/null 2>&1; then
  yum install -y curl-minimal
fi

# ─────────────────────────────────────────────────────────────────
# Install kubectl
# ─────────────────────────────────────────────────────────────────
info "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/
kubectl version --client
info "kubectl installed ✅"

# ─────────────────────────────────────────────────────────────────
# Install eksctl
# ─────────────────────────────────────────────────────────────────
info "Installing eksctl..."
curl --silent --location \
  "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" \
  | tar xz -C /tmp
mv /tmp/eksctl /usr/local/bin/
eksctl version
info "eksctl installed ✅"

# ─────────────────────────────────────────────────────────────────
# Install Helm
# ─────────────────────────────────────────────────────────────────
info "Installing Helm..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
info "Helm installed ✅"

# ─────────────────────────────────────────────────────────────────
# Install AWS CLI
# ─────────────────────────────────────────────────────────────────
info "Installing AWS CLI v2..."
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install --update
rm -rf awscliv2.zip aws
aws --version
info "AWS CLI installed ✅"

# ─────────────────────────────────────────────────────────────────
# Install Docker
# ─────────────────────────────────────────────────────────────────
info "Installing Docker..."
yum install -y docker
systemctl enable --now docker
usermod -aG docker ec2-user || true
chmod 666 /var/run/docker.sock
docker --version
info "Docker installed ✅"

# ─────────────────────────────────────────────────────────────────
# Set kernel params for SonarQube (Elasticsearch requirement)
# ─────────────────────────────────────────────────────────────────
info "Setting kernel parameters for SonarQube..."
tee /etc/sysctl.d/99-sonarqube.conf > /dev/null <<'EOF'
vm.max_map_count=524288
fs.file-max=131072
EOF
sysctl --system

# ─────────────────────────────────────────────────────────────────
# Run SonarQube (Docker)
# ─────────────────────────────────────────────────────────────────
info "Starting SonarQube container..."

docker volume create sonarqube_data
docker volume create sonarqube_logs
docker volume create sonarqube_extensions

# Remove old container if exists
docker rm -f sonarqube >/dev/null 2>&1 || true

if docker run -d \
  --name sonarqube \
  --restart unless-stopped \
  -p 9000:9000 \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_logs:/opt/sonarqube/logs \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  sonarqube:community; then

  info "SonarQube container started. Waiting for initialization..."
  sleep 20

  if ! is_container_running "sonarqube"; then
    warn "SonarQube container exited during startup."
    print_container_logs "sonarqube"
  else
    info "SonarQube is running ✅"
  fi
else
  warn "SonarQube container failed to start."
  print_container_logs "sonarqube"
fi

# ─────────────────────────────────────────────────────────────────
# Add Helm Repos
# ─────────────────────────────────────────────────────────────────
info "Adding Helm repositories..."
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo add external-secrets https://charts.external-secrets.io
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
info "Helm repos added ✅"

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  ✅ BASTION SERVER SETUP COMPLETE!"
echo "=========================================="
echo ""
info "Tools installed:"
echo "  • kubectl      $(kubectl version --client --short 2>/dev/null || echo 'installed')"
echo "  • eksctl       $(eksctl version)"
echo "  • helm         $(helm version --short)"
echo "  • aws          $(aws --version 2>&1 | cut -d' ' -f1)"
echo "  • docker       $(docker --version | cut -d' ' -f3)"
echo ""
info "SonarQube:"
BASTION_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "BASTION_IP")
echo "  • URL:      http://${BASTION_IP}:9000"
echo "  • Login:    admin / admin (change on first login!)"
echo ""
info "Next steps:"
echo "  1. Connect to EKS:  aws eks update-kubeconfig --name food-delivery-cluster --region us-east-1"
echo "  2. Install External Secrets:  bash install-external-secrets.sh"
echo "  3. Update secrets in AWS Secrets Manager via Console"
echo ""
