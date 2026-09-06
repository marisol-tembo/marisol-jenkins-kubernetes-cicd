output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs (kept for Project 1 networking continuity)"
  value       = module.vpc.private_db_subnet_ids
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID (use with SSM)"
  value       = module.jenkins.instance_id
}

output "jenkins_public_ip" {
  description = "Jenkins public IP"
  value       = module.jenkins.public_ip
}

output "jenkins_url" {
  description = "Jenkins UI URL"
  value       = "http://${module.jenkins.public_ip}:8080"
}

output "sonarqube_url" {
  description = "SonarQube UI URL (Docker on Jenkins host)"
  value       = "http://${module.jenkins.public_ip}:9000"
}

output "ecr_repository_url" {
  description = "ECR repository URL for Jenkins Docker push"
  value       = module.ecr.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = module.ecr.repository_arn
}

output "ansible_instance_id" {
  description = "Ansible EC2 instance ID (SSM deploy target)"
  value       = module.ansible.instance_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}
