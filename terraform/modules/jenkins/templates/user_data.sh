#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Jenkins bootstrap at $(date -u)"

# #region agent log
DEBUG_LOG=/var/log/jenkins-bootstrap-debug.ndjson
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"user_data.sh\",\"message\":\"bootstrap_start\",\"data\":{\"curl_pkg\":\"$(rpm -q curl-minimal 2>/dev/null || echo none)\"},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion

# Keep bootstrap moving even if a full OS update is slow/noisy
dnf update -y || echo "dnf update had warnings; continuing"

# Current Jenkins LTS requires Java 21+
# AL2023 ships curl-minimal; installing curl conflicts and aborts the whole transaction.
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"user_data.sh\",\"message\":\"before_base_packages\",\"data\":{\"skip_curl\":true},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion
dnf install -y \
  java-21-amazon-corretto \
  java-21-amazon-corretto-devel \
  docker \
  git \
  maven \
  wget \
  unzip \
  tar
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"A\",\"location\":\"user_data.sh\",\"message\":\"after_base_packages\",\"data\":{\"java_rpm\":\"$(rpm -q java-21-amazon-corretto 2>/dev/null || echo missing)\"},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion

JAVA_HOME_DIR="$(ls -d /usr/lib/jvm/java-21-amazon-corretto* | head -n 1)"
echo "Using JAVA_HOME_DIR=$${JAVA_HOME_DIR}"
test -x "$${JAVA_HOME_DIR}/bin/java"
"$${JAVA_HOME_DIR}/bin/java" -version
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"B\",\"location\":\"user_data.sh\",\"message\":\"java_ok\",\"data\":{\"JAVA_HOME_DIR\":\"$${JAVA_HOME_DIR}\"},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion

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
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"C\",\"location\":\"user_data.sh\",\"message\":\"before_jenkins_pkg\",\"data\":{},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion
dnf install -y jenkins
usermod -aG docker jenkins || true
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"C\",\"location\":\"user_data.sh\",\"message\":\"after_jenkins_pkg\",\"data\":{\"jenkins_rpm\":\"$(rpm -q jenkins 2>/dev/null || echo missing)\"},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion

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
# #region agent log
echo "{\"sessionId\":\"75545d\",\"runId\":\"post-fix\",\"hypothesisId\":\"D\",\"location\":\"user_data.sh\",\"message\":\"bootstrap_complete\",\"data\":{\"jenkins_active\":\"$(systemctl is-active jenkins 2>/dev/null || echo unknown)\"},\"timestamp\":$(date +%s000)}" >> "$${DEBUG_LOG}" || true
# #endregion
echo "Jenkins bootstrap complete at $(date -u)"
