# Phase 2 runbook — Jenkins + SonarQube + ECR

This is the step-by-step path after a fresh `terraform apply`, or after the Jenkins EC2 is replaced.

## Does a git push recreate Jenkins?

**No — not by itself.**

| Action | Recreates Jenkins EC2? |
|--------|------------------------|
| Push `Jenkinsfile`, app code, docs | **No** |
| GitHub Actions `terraform-checks` / `devsecops` on PR | **No** (validate/scan only) |
| GitHub Actions `terraform-deploy` (`workflow_dispatch`) or local `terraform apply` | **Only if** something force-new changes (especially `user_data`) |
| Change `terraform/modules/jenkins/templates/user_data.sh` then apply | **Yes** (`user_data_replace_on_change = true`) |
| IAM / ECR / security group only | **No** (role updates apply to the running instance) |

### What Terraform bootstrap gives you (automatic on new EC2)

From `user_data.sh`:

- Java 21 (Amazon Corretto), Maven, Git, Docker, Trivy
- AWS CLI (already on AL2023 AMI; used for ECR login)
- Jenkins service on port **8080**
- Jenkins user in the `docker` group
- SonarQube Community container on port **9000** (`sonarqube:community`)
- `vm.max_map_count=524288` for Elasticsearch inside SonarQube
- Docker volumes: `sonarqube_data`, `sonarqube_extensions`, `sonarqube_logs`

Also from Terraform:

- ECR repository (immutable tags; Jenkins role can push/pull that repo)
- Security group inbound **8080** and **9000**

### What is still **manual** (lost if EC2 is replaced)

- Jenkins setup wizard / admin password / chosen plugins
- Jenkins credentials (e.g. `sonar-token`, GitHub creds)
- Jenkins jobs (Pipeline config)
- SonarQube admin password change + analysis token
- GitHub webhook (if public IP changed)

---

## 0) Prerequisites (your Mac)

```bash
brew install --cask session-manager-plugin
```

```bash
cd ~/Documents/marisol-devops-projects/marisol-jenkins-kubernetes-cicd/terraform
```

---

## 1) Deploy / refresh infra

```bash
terraform apply
```

Wait for apply + ~5–10 minutes for user-data (Jenkins + Sonar image + Trivy).

```bash
terraform output -raw jenkins_url
terraform output -raw sonarqube_url
terraform output -raw ecr_repository_url
terraform output -raw jenkins_instance_id
```

---

## 2) Unlock Jenkins

1. Open `jenkins_url` (port **8080**).
2. Get the initial admin password:

```bash
aws ssm start-session --target "$(terraform output -raw jenkins_instance_id)"
```

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

3. Unlock Jenkins → install suggested plugins (Git + Pipeline at minimum) → create admin user.

Health checks:

```bash
java -version
mvn -version
docker --version
aws --version
trivy --version
systemctl status jenkins --no-pager
docker ps --filter name=sonarqube
curl -s http://127.0.0.1:9000/api/system/status
```

---

## 3) SonarQube first login

1. Open `sonarqube_url` (port **9000**).
2. Default: `admin` / `admin` → change password.
3. Create a user token: avatar → **My Account** → **Security** → token name e.g. `jenkins`.

Project creation is optional; the first pipeline analysis can create  
`marisol-jenkins-kubernetes-cicd` automatically.

---

## 4) Jenkins credential for Sonar

Jenkins → **Manage Jenkins** → **Credentials** → **(global)** → **Add Credentials**:

- Kind: **Secret text**
- Secret: *(Sonar token)*
- ID: **`sonar-token`** (must match `Jenkinsfile`)

No Sonar Jenkins plugin required (Maven `sonar:sonar` + quality gate wait).  
ECR auth uses the **instance IAM role** — no AWS access keys in Jenkins.

---

## 5) Create the Pipeline job

1. **New Item** → **Pipeline**.
2. Definition: **Pipeline script from SCM** → Git → your repo URL + credentials.
3. Branch: e.g. `*/feature/project3` or `*/main`.
4. Script Path: `Jenkinsfile`.
5. Save.

On **Build with Parameters**:

- `AWS_REGION`: `us-east-1`
- `ECR_REPOSITORY_NAME`: `jenkins-k8s-demo-app` (default; matches Terraform)
- `RUN_SONAR`: `true` (default)

The pipeline **Resolve ECR** stage looks up the full repository URI with the instance IAM role (`aws ecr describe-repositories`) — you do not paste `ecr_repository_url` each run.

Stages: Checkout → Maven Test → SonarQube → Package → Resolve ECR → Docker Build → Trivy Scan → Push to ECR.

Image tag is `BUILD_NUMBER` only (ECR is immutable; no `:latest`).

---

## 6) Optional: auto-build on push

GitHub → **Settings** → **Webhooks** →  
`http://<jenkins-public-ip>:8080/github-webhook/`

---

## 7) Checklist after EC2 replace

Bootstrap brings Jenkins + Sonar + Trivy back (AWS CLI comes with AL2023). Still redo:

- [ ] Unlock Jenkins + plugins + admin user  
- [ ] Sonar first login + new token  
- [ ] Jenkins credential `sonar-token`  
- [ ] Recreate Pipeline job  
- [ ] Confirm `ECR_REPOSITORY_NAME` matches Terraform (default `jenkins-k8s-demo-app`)  
- [ ] Update GitHub webhook if public IP changed  

---

## Manual Sonar recovery (only if container missing)

Bootstrap normally starts Sonar. If you need to recreate it by hand:

```bash
sysctl -w vm.max_map_count=524288
echo "vm.max_map_count=524288" > /etc/sysctl.d/99-sonarqube.conf
docker volume create sonarqube_data
docker volume create sonarqube_extensions
docker volume create sonarqube_logs
docker rm -f sonarqube 2>/dev/null || true
docker run -d --name sonarqube --restart unless-stopped \
  -p 9000:9000 \
  -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
  -v sonarqube_data:/opt/sonarqube/data \
  -v sonarqube_extensions:/opt/sonarqube/extensions \
  -v sonarqube_logs:/opt/sonarqube/logs \
  sonarqube:community
```

Do **not** reuse an old LTS H2 volume with `sonarqube:community` (wipe `sonarqube_data` if you see H2 format errors).

---

## Troubleshooting

```bash
sudo tail -n 100 /var/log/user-data.log
sudo systemctl status jenkins --no-pager
docker logs --tail 80 sonarqube
aws sts get-caller-identity
aws ecr describe-repositories --repository-names "$(terraform output -raw ecr_repository_url | awk -F/ '{print $NF}')"
```

AL2023 note: never `dnf install curl` alongside `curl-minimal` — it aborts the whole package transaction.

Trivy failing the build on HIGH/CRITICAL is expected until base image / deps are cleaned up.

---

## Later

- Ansible EC2 + EKS deploy stages
- SonarCloud if you want GitHub PR decoration (Community does not decorate PRs)
