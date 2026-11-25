# ==============================================================================
# Terraform Main Configuration: main.tf
# Automated Security Compliance & Configuration Drift Detection
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "Lab"
    }
  }
}

# ------------------------------------------------------------------------------
# Networking: Utilize Default VPC and Subnet
# ------------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Dynamically query latest Ubuntu 24.04 LTS Noble AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ------------------------------------------------------------------------------
# Security Groups: Least-Privilege Architecture
# ------------------------------------------------------------------------------

# Security Group 1: Management Server (Puppet Master + Nagios Core)
resource "aws_security_group" "mgmt_sg" {
  name        = "${var.project_name}-mgmt-sg"
  description = "Security Group for Puppet Master and Nagios Core Management Node"
  vpc_id      = data.aws_vpc.default.id

  # Admin SSH Access (Port 22)
  ingress {
    description = "Admin SSH terminal access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Admin Nagios Web Dashboard Access (Port 80)
  ingress {
    description = "Nagios Core HTTP monitoring dashboard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # Puppet Agent Catalog Requests & Certificate CA (Port 8140)
  ingress {
    description = "Puppet Server mTLS catalog access from VPC"
    from_port   = 8140
    to_port     = 8140
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # ICMP Echo / Ping for host alive monitoring
  ingress {
    description = "ICMP Ping from within VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # Outbound access for package updates and NRPE queries
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-mgmt-sg"
  }
}

# Security Group 2: Managed Client Node (Puppet Agent + NRPE)
resource "aws_security_group" "client_sg" {
  name        = "${var.project_name}-client-sg"
  description = "Security Group for Managed Node running Puppet Agent and NRPE"
  vpc_id      = data.aws_vpc.default.id

  # Admin SSH Access (Port 22)
  ingress {
    description = "Admin SSH terminal access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }

  # NRPE Remote Monitoring Probe Execution (Port 5666)
  ingress {
    description = "Nagios NRPE remote probe execution from VPC"
    from_port   = 5666
    to_port     = 5666
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # ICMP Ping from Management Node
  ingress {
    description = "ICMP Ping from within VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  # Outbound access for package downloads and Puppet Master connections
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-client-sg"
  }
}

# ------------------------------------------------------------------------------
# EC2 Compute Instances
# ------------------------------------------------------------------------------

# EC2 Instance 1: Management Server
resource "aws_instance" "mgmt_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.mgmt_instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.mgmt_sg.id]

  root_block_device {
    volume_size           = var.mgmt_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-mgmt"
    Role = "Management-Authority"
  }
}

# EC2 Instance 2: Managed Client Node
resource "aws_instance" "client_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.client_instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.client_sg.id]

  root_block_device {
    volume_size           = var.client_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-client"
    Role = "Managed-Node"
  }
}
