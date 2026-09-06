# Phase 3 runbook — Jenkins + SonarQube + ECR + Ansible + EKS

This is the step-by-step path after a fresh `terraform apply`, or after the Jenkins EC2 is replaced.

**Cost warning:** EKS control plane is ~$0.10/hour even with zero pods. Destroy when idle.

## Does a git push recreate Jenkins?

**No — not by itself.**

| Action | Recreates Jenkins EC2? |
|--------|------------------------|
| Push `Jenkinsfile`, app code, docs | **No** |
| GitHub Actions `terraform-checks` / `devsecops` on PR | **No** (validate/scan only) |
| GitHub Actions `terraform-deploy` (`workflow_dispatch`) or local `terraform apply` | **Only if** something force-new changes (especially `user_data`) |
| Change `terraform/modules/jenkins/templates/user_data.sh` then apply | **Yes** (`user_data_replace_on_change = true`) |
| IAM / ECR / security group only | **No** (role updates apply to the running instance) |

### What Terraform deploys (Phase 3)

- VPC + NAT + security groups
- ECR repository
- Jenkins EC2 (public): Java, Maven, Docker, Trivy, SonarQube container, AWS CLI
- Ansible EC2 (private): Ansible, kubectl, kubeconfig
- EKS cluster + managed node group
- EKS access entry for the Ansible IAM role (cluster admin for lab)
- Jenkins IAM: ECR push + SSM SendCommand to Ansible

### What is still **manual** (lost if Jenkins EC2 is replaced)

- Jenkins setup wizard / admin password / plugins
- Jenkins credentials (`sonar-token`, GitHub)
- Jenkins Pipeline job
- SonarQube admin password + token
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

## 1) Deploy infra

```bash
terraform apply
```

EKS can take **10–15+ minutes**. Then:

```bash
terraform output -raw jenkins_url
terraform output -raw sonarqube_url
terraform output -raw ecr_repository_url
terraform output -raw ansible_instance_id
terraform output -raw eks_cluster_name
terraform output -raw jenkins_instance_id
```

---

## 2) Unlock Jenkins + Sonar (same as Phase 2)

1. Open `jenkins_url` → unlock with SSM initialAdminPassword
2. Install Git + Pipeline plugins → create admin
3. SonarQube: change `admin` password → create token
4. Jenkins credential ID **`sonar-token`** (Secret text)

Health on Jenkins host:

```bash
java -version && mvn -version && docker --version && trivy --version && aws --version
docker ps --filter name=sonarqube
curl -s http://127.0.0.1:9000/api/system/status
```

---

## 3) Pipeline job

1. **New Item** → Pipeline from SCM → this repo / branch / `Jenkinsfile`
2. Build with parameters:

| Param | Typical value |
|-------|----------------|
| `RUN_SONAR` | `true` |
| `DEPLOY` | `true` by default — deploys each new ECR image to EKS (set `false` to build/push only) |

Everything else is discovered automatically:

- **AWS region** — from EC2 instance metadata  
- **ECR** — tags `Project=jenkins-k8s`, `Role=ecr`  
- **Ansible instance** — tags `Project=jenkins-k8s`, `Role=ansible`  
- **EKS cluster** — tags `Project=jenkins-k8s`, `Role=eks`  
- **Git revision for Ansible** — same commit Jenkins built (`git rev-parse HEAD`)

Stages: Checkout → Resolve AWS → Maven → Sonar → Package → Resolve ECR → Docker → Trivy → Push → Deploy (if enabled).

---

## 4) Verify deploy

```bash
aws eks update-kubeconfig --name "$(terraform output -raw eks_cluster_name)" --region us-east-1
kubectl -n demo get deploy,pods,svc
```

Rollback on the Ansible host (via SSM):

```bash
cd /opt/ansible/repo && ansible-playbook ansible/rollback.yml
```

---

## 5) Checklist after Jenkins EC2 replace

- [ ] Unlock Jenkins + plugins + admin
- [ ] Sonar login + token + `sonar-token` credential
- [ ] Recreate Pipeline job
- [ ] Update webhook if IP changed
- [ ] Ansible/EKS usually survive if only Jenkins was replaced

---

## Troubleshooting

```bash
sudo tail -n 100 /var/log/user-data.log
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$(terraform output -raw ansible_instance_id)"
kubectl -n demo describe pods
kubectl -n demo get events --sort-by='.lastTimestamp'
```

AL2023: never `dnf install curl` (conflicts with `curl-minimal`).

---

## Later / production upgrades

- Narrow EKS access policy (not cluster admin)
- Helm or Argo CD instead of Ansible apply
- Private Jenkins + ALB auth
