output "jenkins_security_group_id" {
  description = "Security group ID for Jenkins"
  value       = aws_security_group.jenkins.id
}

output "ansible_security_group_id" {
  description = "Security group ID for Ansible"
  value       = aws_security_group.ansible.id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = aws_security_group.eks_nodes.id
}
