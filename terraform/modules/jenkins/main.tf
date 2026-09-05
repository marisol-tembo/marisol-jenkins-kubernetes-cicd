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
    # Current Jenkins LTS requires Java 21+
    dnf install -y java-21-amazon-corretto java-21-amazon-corretto-devel docker git maven wget unzip tar

    JAVA_HOME_DIR="$(ls -d /usr/lib/jvm/java-21-amazon-corretto* | head -n 1)"

    # Ensure Jenkins systemd unit can find Java 21
    mkdir -p /etc/systemd/system/jenkins.service.d
    cat > /etc/systemd/system/jenkins.service.d/override.conf <<UNIT
[Service]
Environment="JAVA_HOME=$${JAVA_HOME_DIR}"
UNIT

    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Jenkins package install
    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins
    usermod -aG docker jenkins

    # Point Jenkins at Java 21 explicitly (AL2023)
    if [ -f /etc/sysconfig/jenkins ]; then
      sed -i "s|^JENKINS_JAVA_CMD=.*|JENKINS_JAVA_CMD=\"$${JAVA_HOME_DIR}/bin/java\"|" /etc/sysconfig/jenkins || true
    fi

    systemctl daemon-reload
    systemctl enable jenkins
    systemctl start jenkins

    # Wait until Jenkins responds on 8080
    for i in $(seq 1 60); do
      if curl -fsS http://127.0.0.1:8080/login >/dev/null 2>&1; then
        echo "Jenkins is up"
        break
      fi
      sleep 5
    done

    systemctl is-active --quiet jenkins
    echo "Jenkins bootstrap complete (Phase 1: Jenkins only, Java 21)"
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
