# Outputs for bastion host

locals {
  bastion_created = var.create_bastion_host && (var.deployment_stage == "stage1" || var.deployment_stage == "all")
}

output "bastion_instance_id" {
  description = "Instance ID of the bastion host (use with AWS Session Manager)"
  value       = local.bastion_created ? aws_instance.bastion[0].id : null
}

output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = local.bastion_created ? aws_instance.bastion[0].public_ip : null
}

output "bastion_connect_command" {
  description = "Command to connect to bastion via Session Manager"
  value       = local.bastion_created ? "aws ssm start-session --target ${aws_instance.bastion[0].id}" : "Bastion not created (set deployment_stage=stage1)"
}

output "bastion_ssh_command" {
  description = "Command to SSH to bastion (requires SSH key)"
  value       = local.bastion_created ? "ssh ec2-user@${aws_instance.bastion[0].public_ip}" : "Bastion not created (set deployment_stage=stage1)"
}

