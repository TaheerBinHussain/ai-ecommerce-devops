variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "root_volume_size" {
  type = number
}

variable "ssh_public_key_path" {
  type = string
}

variable "admin_cidrs" {
  type = list(string)
}

variable "ecr_repository_arn" {
  type = string
}
