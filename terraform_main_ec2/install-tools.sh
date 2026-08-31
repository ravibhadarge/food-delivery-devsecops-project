#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log) 2>&1

echo "=========================================="
echo "     DEVOPS EC2 USER DATA START"
echo "=========================================="

# ------------------------------------------
# SYSTEM UPDATE
# ------------------------------------------

echo "===== SYSTEM UPDATE ====="

dnf update -y

# ------------------------------------------
# BASIC PACKAGES
# ------------------------------------------

echo "===== BASIC PACKAGES ====="

dnf install -y \
    git \
    wget \
    unzip \
    curl \
    jq \
    tar \
    gzip \
    vim \
    fontconfig \
    yum-utils

# ------------------------------------------
# JAVA 21
# ------------------------------------------

echo "===== JAVA 21 ====="

dnf install -y java-21-amazon-corretto-devel

cat > /etc/profile.d/java21.sh <<'EOF'
export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto
export PATH=$JAVA_HOME/bin:$PATH
EOF

chmod +x /etc/profile.d/java21.sh

export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto
export PATH=$JAVA_HOME/bin:$PATH

java -version

# ------------------------------------------
# NODEJS 22
# ------------------------------------------

echo "===== NODEJS 22 ====="

curl -fsSL https://rpm.nodesource.com/setup_22.x | bash -

dnf install -y nodejs

node -v
npm -v

# ------------------------------------------
# JENKINS
# ------------------------------------------

echo "===== JENKINS ====="

wget -O /etc/yum.repos.d/jenkins.repo \
    https://pkg.jenkins.io/rpm-stable/jenkins.repo

rpm --import \
    https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key

dnf install -y jenkins

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# ------------------------------------------
# MAVEN
# ------------------------------------------

echo "===== MAVEN ====="

dnf install -y maven

mvn -version

# ------------------------------------------
# TERRAFORM
# ------------------------------------------

echo "===== TERRAFORM ====="

yum-config-manager \
    --add-repo \
    https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo

dnf install -y terraform

terraform version

# ------------------------------------------
# ANSIBLE
# ------------------------------------------

echo "===== ANSIBLE ====="

dnf install -y ansible

ansible --version

# ------------------------------------------
# DOCKER
# ------------------------------------------

echo "===== DOCKER ====="

dnf install -y docker

systemctl enable docker
systemctl start docker

usermod -aG docker ec2-user
usermod -aG docker jenkins

# Docker socket
chmod 666 /var/run/docker.sock

docker --version

# ------------------------------------------
# DOCKER COMPOSE
# ------------------------------------------

echo "===== DOCKER COMPOSE ====="

mkdir -p /usr/local/lib/docker/cli-plugins

curl -SL \
    https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose

chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

docker compose version

# ------------------------------------------
# AWS CLI V2
# ------------------------------------------

echo "===== AWS CLI V2 ====="

cd /tmp

rm -rf aws awscliv2.zip

curl -fsSL \
    https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip \
    -o awscliv2.zip

unzip -q awscliv2.zip

./aws/install --update

rm -rf aws awscliv2.zip

/usr/local/bin/aws --version

# ------------------------------------------
# GITHUB CLI
# ------------------------------------------

echo "===== GITHUB CLI ====="

dnf install -y 'dnf-command(config-manager)'

dnf config-manager \
    --add-repo \
    https://cli.github.com/packages/rpm/gh-cli.repo

rpm --import \
    https://cli.github.com/packages/githubcli-archive-keyring.gpg

dnf install -y gh

gh --version

# ------------------------------------------
# KUBECTL
# ------------------------------------------

echo "===== KUBECTL ====="

KUBECTL_VERSION=$(curl -L -s \
    https://dl.k8s.io/release/stable.txt)

curl -LO \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

install -o root -g root -m 0755 \
    kubectl /usr/local/bin/kubectl

rm -f kubectl

kubectl version --client

# ------------------------------------------
# EKSCTL
# ------------------------------------------

echo "===== EKSCTL ====="

EKSCTL_VERSION=$(curl -sL \
    https://api.github.com/repos/eksctl-io/eksctl/releases/latest \
    | jq -r '.tag_name')

curl -L \
    "https://github.com/eksctl-io/eksctl/releases/download/${EKSCTL_VERSION}/eksctl_${EKSCTL_VERSION#v}_Linux_amd64.tar.gz" \
    -o /tmp/eksctl.tar.gz

tar -xzf /tmp/eksctl.tar.gz -C /tmp

install -m 0755 \
    /tmp/eksctl /usr/local/bin/eksctl

rm -f /tmp/eksctl /tmp/eksctl.tar.gz

eksctl version

# ------------------------------------------
# HELM
# ------------------------------------------

echo "===== HELM ====="

curl -fsSL \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \
    | bash

helm version

# ------------------------------------------
# TRIVY
# ------------------------------------------

echo "===== TRIVY ====="

TRIVY_VERSION=$(curl -s \
    https://api.github.com/repos/aquasecurity/trivy/releases/latest \
    | jq -r '.tag_name')

curl -LO \
    "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_Linux-64bit.rpm"

rpm -Uvh \
    "trivy_${TRIVY_VERSION#v}_Linux-64bit.rpm"

rm -f \
    "trivy_${TRIVY_VERSION#v}_Linux-64bit.rpm"

trivy --version

# ------------------------------------------
# VAULT
# ------------------------------------------

echo "===== VAULT ====="

dnf install -y vault

vault version || true

# ------------------------------------------
# MARIADB
# ------------------------------------------

echo "===== MARIADB ====="

dnf install -y mariadb105-server

systemctl enable mariadb
systemctl start mariadb

mysql --version

# ------------------------------------------
# POSTGRESQL
# ------------------------------------------

echo "===== POSTGRESQL ====="

dnf install -y postgresql15 postgresql15-server

if [ ! -f /var/lib/pgsql/15/data/PG_VERSION ]; then
    /usr/pgsql-15/bin/postgresql-15-setup initdb
fi

systemctl enable postgresql-15
systemctl start postgresql-15

psql --version

# ------------------------------------------
# JENKINS DOCKER PERMISSION
# ------------------------------------------

echo "===== JENKINS DOCKER PERMISSION ====="

usermod -aG docker jenkins

systemctl restart docker
systemctl restart jenkins

# ------------------------------------------
# SONARQUBE
# ------------------------------------------

echo "===== SONARQUBE ====="

docker rm -f sonar 2>/dev/null || true

docker run -d \
    --name sonar \
    --restart unless-stopped \
    -p 9000:9000 \
    sonarqube:lts-community

docker ps

# ------------------------------------------
# FINAL CHECK
# ------------------------------------------

echo "=========================================="
echo "        INSTALLATION COMPLETE"
echo "=========================================="

echo "Java:"
java -version

echo "Node:"
node -v

echo "NPM:"
npm -v

echo "Git:"
git --version

echo "Maven:"
mvn --version

echo "Terraform:"
terraform version

echo "Ansible:"
ansible --version

echo "Docker:"
docker --version

echo "Docker Compose:"
docker compose version

echo "AWS CLI:"
aws --version

echo "GitHub CLI:"
gh --version

echo "kubectl:"
kubectl version --client

echo "Helm:"
helm version

echo "eksctl:"
eksctl version

echo "Trivy:"
trivy --version

echo "Vault:"
vault version || true

echo "=========================================="
echo "        JENKINS STATUS"
echo "=========================================="

systemctl --no-pager status jenkins || true

echo "=========================================="
echo "        DOCKER STATUS"
echo "=========================================="

systemctl --no-pager status docker || true

echo "=========================================="
echo "        SONARQUBE"
echo "=========================================="

docker ps

echo "=========================================="
echo "      DEVOPS SETUP FINISHED"
echo "=========================================="

echo "Jenkins:"
echo "http://YOUR-EC2-PUBLIC-IP:8080"

echo "SonarQube:"
echo "http://YOUR-EC2-PUBLIC-IP:9000"

echo "Jenkins Initial Password:"

if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
    cat /var/lib/jenkins/secrets/initialAdminPassword
fi

echo ""
echo "User-data log:"
echo "/var/log/user-data.log"

echo "=========================================="
