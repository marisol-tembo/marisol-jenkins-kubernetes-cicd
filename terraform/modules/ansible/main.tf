data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_region" "current" {}

resource "aws_iam_role" "ansible" {
  name = "${var.name}-ansible-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.name}-ansible-role"
  }
}

resource "aws_iam_role_policy_attachment" "ansible_ssm" {
  role       = aws_iam_role.ansible.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ansible_eks" {
  name = "${var.name}-ansible-eks"
  role = aws_iam_role.ansible.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EksClusterAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:AccessKubernetesApi"
        ]
        Resource = var.eks_cluster_arn
      },
      {
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ]
        Resource = "arn:aws:ecr:*:*:repository/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ansible" {
  name = "${var.name}-ansible-profile"
  role = aws_iam_role.ansible.name
}

locals {
  ansible_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    dnf update -y
    dnf install -y python3 python3-pip git unzip

    pip3 install --upgrade pip
    pip3 install ansible kubernetes kubernetes-client

    # kubectl
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x /usr/local/bin/kubectl

    if ! command -v aws >/dev/null 2>&1; then
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp
      /tmp/aws/install
    fi

    mkdir -p /opt/ansible /home/ec2-user/.kube
    chown -R ec2-user:ec2-user /opt/ansible /home/ec2-user/.kube

    # Configure kubeconfig for the EKS cluster
    aws eks update-kubeconfig \
      --region ${data.aws_region.current.region} \
      --name ${var.eks_cluster_name} \
      --kubeconfig /home/ec2-user/.kube/config
    chown ec2-user:ec2-user /home/ec2-user/.kube/config

    echo "Ansible bootstrap complete"
  EOF
}

resource "aws_instance" "ansible" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.ansible.name
  associate_public_ip_address = false
  ebs_optimized               = true
  user_data                   = local.ansible_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-ansible"
    Role = "ansible"
  }
}
