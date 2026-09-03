resource "aws_security_group" "jenkins" {
  name        = "${var.name}-jenkins-sg"
  description = "Jenkins CI host security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-jenkins-sg"
  }
}

resource "aws_security_group" "ansible" {
  name        = "${var.name}-ansible-sg"
  description = "Ansible deploy host security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-ansible-sg"
  }
}

resource "aws_security_group" "eks_nodes" {
  name        = "${var.name}-eks-nodes-sg"
  description = "EKS worker node security group"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-eks-nodes-sg"
  }
}

# Jenkins: allow HTTPS UI from internet for lab demos; admin still preferred via SSM.
resource "aws_security_group_rule" "jenkins_ingress_https" {
  type              = "ingress"
  description       = "Jenkins UI HTTPS from internet"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins.id
}

resource "aws_security_group_rule" "jenkins_egress_https" {
  type              = "egress"
  description       = "HTTPS outbound for packages, GitHub, Sonar, ECR"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins.id
}

resource "aws_security_group_rule" "jenkins_egress_http" {
  type              = "egress"
  description       = "HTTP outbound for package mirrors"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins.id
}

resource "aws_security_group_rule" "jenkins_egress_dns_udp" {
  type              = "egress"
  description       = "DNS resolution UDP"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins.id
}

resource "aws_security_group_rule" "jenkins_egress_dns_tcp" {
  type              = "egress"
  description       = "DNS resolution TCP"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins.id
}

# Jenkins can SSH to Ansible for deploy handoff if needed.
resource "aws_security_group_rule" "jenkins_egress_ssh_ansible" {
  type                     = "egress"
  description              = "SSH to Ansible deploy host"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.jenkins.id
  source_security_group_id = aws_security_group.ansible.id
}

resource "aws_security_group_rule" "ansible_ingress_ssh_jenkins" {
  type                     = "ingress"
  description              = "SSH from Jenkins only"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ansible.id
  source_security_group_id = aws_security_group.jenkins.id
}

resource "aws_security_group_rule" "ansible_egress_https" {
  type              = "egress"
  description       = "HTTPS outbound for EKS API, ECR auth, packages"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ansible.id
}

resource "aws_security_group_rule" "ansible_egress_http" {
  type              = "egress"
  description       = "HTTP outbound for package mirrors"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ansible.id
}

resource "aws_security_group_rule" "ansible_egress_dns_udp" {
  type              = "egress"
  description       = "DNS resolution UDP"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ansible.id
}

resource "aws_security_group_rule" "ansible_egress_dns_tcp" {
  type              = "egress"
  description       = "DNS resolution TCP"
  from_port         = 53
  to_port           = 53
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ansible.id
}

# EKS nodes: allow node-to-node and kubelet communication patterns.
resource "aws_security_group_rule" "eks_nodes_ingress_self" {
  type              = "ingress"
  description       = "Node to node communication"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "eks_nodes_egress_all" {
  type              = "egress"
  description       = "Outbound for nodes (images, API, DNS)"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_nodes.id
}
