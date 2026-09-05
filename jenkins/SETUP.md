# Phase 1 — Jenkins only

Focus first on getting Jenkins up and usable. Local SonarQube (Docker on the Jenkins host) comes next.

Bootstrap script lives in:

`terraform/modules/jenkins/templates/user_data.sh`

Terraform is configured with `user_data_replace_on_change = true`, so changing that script replaces the Jenkins EC2 and re-runs bootstrap.

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
   - Current stages only: Checkout → Maven Test → SonarQube
   - Docker / Trivy / ECR / Deploy stages are removed until later phases

## SonarQube on the Jenkins host (Docker)

1. SonarQube Community container listens on `http://127.0.0.1:9000` (and optionally the public IP:9000 if the security group allows it).
2. In Jenkins → Credentials, add Secret text ID `sonar-token` (SonarQube user token).
3. Push the updated `Jenkinsfile`, then run the Pipeline (`RUN_SONAR` defaults to `true`).
4. The first analysis creates the Sonar project automatically (`marisol-jenkins-kubernetes-cicd`).
5. Confirm results in the SonarQube UI and that the quality gate did not fail the Jenkins stage.

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

- **ECR / Docker / Trivy:** enable image build and scan (needs ECR from Terraform)
- **Ansible + EKS:** enable deploy
- **Optional:** SonarCloud later if you want GitHub PR decoration

## Notes

- ECR, Ansible EC2, and EKS modules stay in the repo but are not applied in Phase 1.
- Local Sonar uses the Maven `sonar:sonar` plugin (already in `app/pom.xml`); no separate scanner install required.
