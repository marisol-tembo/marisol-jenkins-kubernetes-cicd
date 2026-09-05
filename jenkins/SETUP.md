# Phase 1 — Jenkins only

Focus first on getting Jenkins up and usable. SonarCloud comes next.

After `terraform apply`:

1. Open the Jenkins URL:
   ```bash
   terraform output -raw jenkins_url
   ```

2. Get the initial admin password via SSM:
   ```bash
   aws ssm start-session --target "$(terraform output -raw jenkins_instance_id)"
   sudo cat /var/lib/jenkins/secrets/initialAdminPassword
   ```

3. Complete the Jenkins setup wizard.

4. Confirm Jenkins is healthy:
   - UI loads on port 8080
   - You can create a Pipeline job
   - Maven and Docker are available on the host:
     ```bash
     java -version
     mvn -version
     docker --version
     ```

5. In the setup wizard, install the suggested plugins (or at least Git + Pipeline).

6. Create a Pipeline job pointing to this repository `Jenkinsfile`.
   - Keep `RUN_SONAR=false`
   - Keep `DEPLOY=false`
   - For now, validate Checkout + Maven Test stages

## If Jenkins service fails

On the instance via SSM:

```bash
sudo journalctl -u jenkins -n 100 --no-pager
sudo tail -n 100 /var/log/jenkins/jenkins.log
sudo systemctl status jenkins --no-pager
```

Common recovery (Java 21 required by current Jenkins):

```bash
sudo dnf install -y java-21-amazon-corretto java-21-amazon-corretto-devel
JAVA_HOME_DIR="$(ls -d /usr/lib/jvm/java-21-amazon-corretto* | head -n 1)"
sudo mkdir -p /etc/systemd/system/jenkins.service.d
echo -e "[Service]\nEnvironment=\"JAVA_HOME=$JAVA_HOME_DIR\"" | sudo tee /etc/systemd/system/jenkins.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl restart jenkins
sudo systemctl status jenkins --no-pager
```

## Later phases

- **SonarCloud:** add token credential `sonar-token`, install Sonar plugin/scanner, set `RUN_SONAR=true`
- **ECR / Docker / Trivy:** enable image build and scan
- **Ansible + EKS:** enable deploy

## Notes

- ECR, Ansible EC2, and EKS modules stay in the repo but are not applied in Phase 1.
- SonarScanner is intentionally not installed yet.
