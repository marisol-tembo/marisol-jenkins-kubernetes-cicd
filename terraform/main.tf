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

module "ecr" {
  source = "./modules/ecr"

  name            = var.name
  repository_name = var.ecr_repository_name
}

# Phase 2: Jenkins + ECR. Ansible and EKS come later.
module "jenkins" {
  source = "./modules/jenkins"

  name               = var.name
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_id  = module.security.jenkins_security_group_id
  instance_type      = var.jenkins_instance_type
  ecr_repository_arn = module.ecr.repository_arn
}
