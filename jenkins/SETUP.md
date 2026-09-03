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

5. Create a Pipeline job pointing to this repository `Jenkinsfile`.
   - Keep `RUN_SONAR=false`
   - Keep `DEPLOY=false`
   - For now, validate Checkout + Maven Test stages

## Later phases

- **SonarCloud:** add token credential `sonar-token`, install Sonar plugin/scanner, set `RUN_SONAR=true`
- **ECR / Docker / Trivy:** enable image build and scan
- **Ansible + EKS:** enable deploy

## Notes

- ECR, Ansible EC2, and EKS modules stay in the repo but are not applied in Phase 1.
- SonarScanner is intentionally not installed yet.
