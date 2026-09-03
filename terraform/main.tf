module "vpc" {
  source = "./modules/vpc"

  name       = var.name
  cidr_block = var.vpc_cidr_block
}

module "security" {
  source = "./modules/security"

  name           = var.name
  vpc_id         = module.vpc.vpc_id
  vpc_cidr_block = module.vpc.vpc_cidr_block
}

# Phase 1: Jenkins only.
# ECR, Ansible, and EKS modules will be enabled in later phases.
module "jenkins" {
  source = "./modules/jenkins"

  name              = var.name
  subnet_id         = module.vpc.public_subnet_ids[0]
  security_group_id = module.security.jenkins_security_group_id
  instance_type     = var.jenkins_instance_type
}
