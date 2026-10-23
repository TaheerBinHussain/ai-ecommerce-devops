output "node_public_ip" {
  description = "Elastic IP of the k3s node"
  value       = module.compute.public_ip
}

output "ssh_command" {
  description = "SSH into the node"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${module.compute.public_ip}"
}

output "ecr_repository_url" {
  description = "Push application images here (Jenkins IMAGE_REPO for the aws target)"
  value       = module.registry.repository_url
}

output "ansible_inventory" {
  description = "Generated inventory file for ansible-playbook -i"
  value       = local_file.ansible_inventory.filename
}

output "vpc_id" {
  value = module.network.vpc_id
}
