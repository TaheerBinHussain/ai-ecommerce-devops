# AI-Powered E-Commerce DevOps platform - AWS infrastructure
#   VPC + public subnet  ->  EC2 node (k3s installed by Ansible)  +  ECR image registry

locals {
  name = "${var.project_name}-${var.environment}"
}

module "network" {
  source             = "./modules/network"
  name               = local.name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "registry" {
  source          = "./modules/registry"
  repository_name = "${var.project_name}-store"
}

module "compute" {
  source              = "./modules/compute"
  name                = local.name
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.public_subnet_id
  instance_type       = var.instance_type
  root_volume_size    = var.root_volume_size
  ssh_public_key_path = var.ssh_public_key_path
  admin_cidrs         = var.admin_cidrs
  ecr_repository_arn  = module.registry.repository_arn
}

# Hand-off to configuration management: Terraform writes the Ansible inventory.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/${var.environment}.ini"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/inventory.ini.tftpl", {
    environment      = var.environment
    host_ip          = module.compute.public_ip
    private_key_path = var.ssh_private_key_path
    ecr_registry     = split("/", module.registry.repository_url)[0]
    ecr_repository   = module.registry.repository_url
    aws_region       = var.aws_region
  })
}
