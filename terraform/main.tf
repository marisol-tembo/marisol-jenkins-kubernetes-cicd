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

# Phase 3: Jenkins + ECR + Ansible + EKS
module "eks" {
  source = "./modules/eks"

  name                       = var.name
  private_subnet_ids         = module.vpc.private_app_subnet_ids
  public_subnet_ids          = module.vpc.public_subnet_ids
  cluster_security_group_ids = []
  node_security_group_id     = module.security.eks_nodes_security_group_id
  node_instance_type         = var.eks_node_instance_type
  node_desired_size          = var.eks_node_desired_size
  node_min_size              = var.eks_node_min_size
  node_max_size              = var.eks_node_max_size
}

module "ansible" {
  source = "./modules/ansible"

  name              = var.name
  subnet_id         = module.vpc.private_app_subnet_ids[0]
  security_group_id = module.security.ansible_security_group_id
  instance_type     = var.ansible_instance_type
  eks_cluster_name  = module.eks.cluster_name
  eks_cluster_arn   = module.eks.cluster_arn

  depends_on = [module.eks]
}

# Allow Ansible instance role to use kubectl against the cluster (EKS Access Entries API)
resource "aws_eks_access_entry" "ansible" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.ansible.iam_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "ansible_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.ansible.iam_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.ansible]
}

module "jenkins" {
  source = "./modules/jenkins"

  name                = var.name
  subnet_id           = module.vpc.public_subnet_ids[0]
  security_group_id   = module.security.jenkins_security_group_id
  instance_type       = var.jenkins_instance_type
  ecr_repository_arn  = module.ecr.repository_arn
  ansible_instance_id = module.ansible.instance_id
}
