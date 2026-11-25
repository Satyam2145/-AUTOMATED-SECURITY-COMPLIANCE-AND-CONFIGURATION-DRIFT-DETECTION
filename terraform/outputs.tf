# ==============================================================================
# Terraform Outputs: outputs.tf
# Automated Security Compliance & Configuration Drift Detection
# ==============================================================================

output "mgmt_server_public_ip" {
  description = "Public IPv4 address of Management Server (Puppet Master + Nagios Core)"
  value       = aws_instance.mgmt_server.public_ip
}

output "mgmt_server_private_ip" {
  description = "Private IPv4 address of Management Server"
  value       = aws_instance.mgmt_server.private_ip
}

output "client_server_public_ip" {
  description = "Public IPv4 address of Managed Client Node (Puppet Agent + NRPE)"
  value       = aws_instance.client_server.public_ip
}

output "client_server_private_ip" {
  description = "Private IPv4 address of Managed Client Node"
  value       = aws_instance.client_server.private_ip
}

output "nagios_web_console_url" {
  description = "Nagios Core Web UI Access URL"
  value       = "http://${aws_instance.mgmt_server.public_ip}/nagios/"
}

output "ssh_management_server" {
  description = "Command to connect via SSH to Management Server"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.mgmt_server.public_ip}"
}

output "ssh_managed_client" {
  description = "Command to connect via SSH to Managed Client"
  value       = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.client_server.public_ip}"
}

output "etc_hosts_snippet" {
  description = "DNS mapping block to append to /etc/hosts on both EC2 nodes"
  value       = <<-EOT
    ${aws_instance.mgmt_server.private_ip}   puppetmaster.ec2.internal puppetmaster puppet
    ${aws_instance.client_server.private_ip}   client.ec2.internal client
  EOT
}

output "ansible_inventory_snippet" {
  description = "Ready-to-use Ansible inventory block for ansible/inventory/hosts.ini"
  value       = <<-EOT
    [mgmt_server]
    puppetmaster ansible_host=${aws_instance.mgmt_server.public_ip} private_ip=${aws_instance.mgmt_server.private_ip}

    [client_nodes]
    client ansible_host=${aws_instance.client_server.public_ip} private_ip=${aws_instance.client_server.private_ip}

    [all:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=~/.ssh/${var.key_name}.pem
    ansible_python_interpreter=/usr/bin/python3
  EOT
}
