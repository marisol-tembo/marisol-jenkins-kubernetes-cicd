#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Jenkins + SonarQube bootstrap at $(date -u)"

# Keep bootstrap moving even if a full OS update is slow/noisy
dnf update -y || echo "dnf update had warnings; continuing"

# Current Jenkins LTS requires Java 21+
# AL2023 ships curl-minimal; installing curl conflicts and aborts the whole transaction.
# AWS CLI is already present on AL2023 (used for ecr get-login-password).
dnf install -y \
  java-21-amazon-corretto \
  java-21-amazon-corretto-devel \
  docker \
  git \
  maven \
  wget \
  unzip \
  tar

# Trivy for container image scanning in the Jenkins pipeline
rpm --import https://aquasecurity.github.io/trivy-repo/rpm/public.key
cat > /etc/yum.repos.d/trivy.repo <<'EOF'
[trivy]
name=Trivy repository
baseurl=https://aquasecurity.github.io/trivy-repo/rpm/releases/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://aquasecurity.github.io/trivy-repo/rpm/public.key
EOF
dnf install -y trivy
trivy --version
aws --version

JAVA_HOME_DIR="$(ls -d /usr/lib/jvm/java-21-amazon-corretto* | head -n 1)"
echo "Using JAVA_HOME_DIR=$${JAVA_HOME_DIR}"
test -x "$${JAVA_HOME_DIR}/bin/java"
"$${JAVA_HOME_DIR}/bin/java" -version

# Point Jenkins systemd unit at Java 21
mkdir -p /etc/systemd/system/jenkins.service.d
printf '%s\n' \
  '[Service]' \
  "Environment=\"JAVA_HOME=$${JAVA_HOME_DIR}\"" \
  > /etc/systemd/system/jenkins.service.d/override.conf

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user || true

# Jenkins package install
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
dnf install -y jenkins
usermod -aG docker jenkins || true

# Optional legacy sysconfig override if present
if [ -f /etc/sysconfig/jenkins ]; then
  if grep -q '^JENKINS_JAVA_CMD=' /etc/sysconfig/jenkins; then
    sed -i "s|^JENKINS_JAVA_CMD=.*|JENKINS_JAVA_CMD=\"$${JAVA_HOME_DIR}/bin/java\"|" /etc/sysconfig/jenkins
  else
    echo "JENKINS_JAVA_CMD=\"$${JAVA_HOME_DIR}/bin/java\"" >> /etc/sysconfig/jenkins
  fi
fi

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# Wait until Jenkins responds on 8080 (curl-minimal provides curl)
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
    echo "Jenkins is up"
    break
  fi
  echo "Waiting for Jenkins... attempt $${i}"
  sleep 5
done

systemctl is-active --quiet jenkins
systemctl status jenkins --no-pager || true

# ---------------------------------------------------------------------------
# SonarQube Community in Docker (same host; used by Jenkins at 127.0.0.1:9000)
# ---------------------------------------------------------------------------
sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" > /etc/sysctl.d/99-sonarqube.conf

docker volume create sonarqube_data
docker volume create sonarqube_extensions
docker volume create sonarqube_logs

# Idempotent: replace any previous container with the same name
docker rm -f sonarqube 2>/dev/null || true

docker run -d --name sonarqube --restart unless-stopped \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  -v sonarqube_logs:/opt/sonarqube/logs \
  sonarqube:community

for i in $(seq 1 90); do
  if curl -fsS http://127.0.0.1:9000/api/system/status 2>/dev/null | grep -q '"status":"UP"'; then
    echo "SonarQube is up"
    break
  fi
  echo "Waiting for SonarQube... attempt $${i}"
  sleep 5
done

docker ps --filter name=sonarqube --no-trunc || true
curl -s http://127.0.0.1:9000/api/system/status || true

echo "Jenkins + SonarQube + ECR tools bootstrap complete at $(date -u)"
