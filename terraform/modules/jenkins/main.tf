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

resource "aws_iam_role" "jenkins" {
  name = "${var.name}-jenkins-role"

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
    Name = "${var.name}-jenkins-role"
  }
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.name}-jenkins-profile"
  role = aws_iam_role.jenkins.name
}

locals {
  jenkins_user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

    dnf update -y
    dnf install -y java-17-amazon-corretto docker git maven wget unzip tar

    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Jenkins
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins
    usermod -aG docker jenkins
    systemctl enable jenkins
    systemctl start jenkins

    # Wait for Jenkins to come up, then install core pipeline plugins only
    for i in $(seq 1 60); do
      if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
        break
      fi
      sleep 5
    done

    if command -v jenkins-plugin-cli >/dev/null 2>&1; then
      jenkins-plugin-cli --plugins \
        git \
        workflow-aggregator \
        credentials \
        credentials-binding \
        junit \
        pipeline-stage-view
      systemctl restart jenkins
    fi

    # AWS CLI v2 is usually present on AL2023; ensure available
    if ! command -v aws >/dev/null 2>&1; then
      curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
      unzip -q /tmp/awscliv2.zip -d /tmp
      /tmp/aws/install
    fi

    echo "Jenkins bootstrap complete (Phase 1: Jenkins only)"
  EOF
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  ebs_optimized               = true
  user_data                   = local.jenkins_user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "${var.name}-jenkins"
    Role = "jenkins"
  }
}
