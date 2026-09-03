output "instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = aws_instance.jenkins.id
}

output "private_ip" {
  description = "Jenkins private IP"
  value       = aws_instance.jenkins.private_ip
}

output "public_ip" {
  description = "Jenkins public IP"
  value       = aws_instance.jenkins.public_ip
}

output "iam_role_name" {
  description = "Jenkins IAM role name"
  value       = aws_iam_role.jenkins.name
}

output "iam_role_arn" {
  description = "Jenkins IAM role ARN"
  value       = aws_iam_role.jenkins.arn
}
