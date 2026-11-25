# ==============================================================================
# Terraform Variables: variables.tf
# Automated Security Compliance & Configuration Drift Detection
# ==============================================================================

variable "aws_region" {
  description = "The target AWS Region for infrastructure deployment"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project prefix for resource naming and tagging"
  type        = string
  default     = "sec-compliance"
}

variable "key_name" {
  description = "Name of an existing AWS EC2 Key Pair used for SSH authentication"
  type        = string
  default     = "devops-sec-key"
}

variable "admin_ip" {
  description = "Administrator public IP CIDR allowed for SSH (22) and Nagios Web (80) access"
  type        = string
  default     = "0.0.0.0/0" # Recommended in production: "YOUR_PUBLIC_IP/32"
}

variable "mgmt_instance_type" {
  description = "EC2 Instance type for the Management Server (Puppet Server + Nagios Core)"
  type        = string
  default     = "t3.medium"
}

variable "client_instance_type" {
  description = "EC2 Instance type for the Managed Client (Puppet Agent + NRPE)"
  type        = string
  default     = "t3.micro"
}

variable "mgmt_volume_size" {
  description = "Root EBS storage size in GB for Management Server"
  type        = number
  default     = 30
}

variable "client_volume_size" {
  description = "Root EBS storage size in GB for Managed Client"
  type        = number
  default     = 20
}
