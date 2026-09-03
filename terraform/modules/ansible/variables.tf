variable "name" {
  description = "Name prefix"
  type        = string
}

variable "subnet_id" {
  description = "Private app subnet ID for Ansible"
  type        = string
}

variable "security_group_id" {
  description = "Ansible security group ID"
  type        = string
}

variable "instance_type" {
  description = "Ansible EC2 instance type"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name for kubeconfig bootstrap"
  type        = string
}

variable "eks_cluster_arn" {
  description = "EKS cluster ARN for IAM permissions"
  type        = string
}
