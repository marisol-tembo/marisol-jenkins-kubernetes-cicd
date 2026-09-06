variable "name" {
  description = "Name prefix"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for Jenkins"
  type        = string
}

variable "security_group_id" {
  description = "Jenkins security group ID"
  type        = string
}

variable "instance_type" {
  description = "Jenkins EC2 instance type"
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN Jenkins may push/pull"
  type        = string
}
