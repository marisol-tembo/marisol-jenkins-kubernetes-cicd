variable "name" {
  description = "Name prefix / cluster name base"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private app subnet IDs for EKS"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for optional load balancers"
  type        = list(string)
}

variable "cluster_security_group_ids" {
  description = "Additional security groups for the cluster (optional node SG attachment helpers)"
  type        = list(string)
  default     = []
}

variable "node_security_group_id" {
  description = "Security group for EKS worker nodes"
  type        = string
}

variable "node_instance_type" {
  description = "Instance type for managed node group"
  type        = string
}

variable "node_desired_size" {
  description = "Desired node count"
  type        = number
}

variable "node_min_size" {
  description = "Minimum node count"
  type        = number
}

variable "node_max_size" {
  description = "Maximum node count"
  type        = number
}
