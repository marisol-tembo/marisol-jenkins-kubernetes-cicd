output "instance_id" {
  description = "Ansible EC2 instance ID"
  value       = aws_instance.ansible.id
}

output "private_ip" {
  description = "Ansible private IP"
  value       = aws_instance.ansible.private_ip
}

output "iam_role_name" {
  description = "Ansible IAM role name"
  value       = aws_iam_role.ansible.name
}

output "iam_role_arn" {
  description = "Ansible IAM role ARN"
  value       = aws_iam_role.ansible.arn
}
