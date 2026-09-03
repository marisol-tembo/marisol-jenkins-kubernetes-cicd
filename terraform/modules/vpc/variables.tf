variable "name" {
  description = "Name prefix for VPC resources"
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block"
  type        = string
}

variable "availability_zones" {
  description = "Availability Zones for the VPC"
  type        = list(string)

  default = [
    "us-east-1a",
    "us-east-1b"
  ]
}