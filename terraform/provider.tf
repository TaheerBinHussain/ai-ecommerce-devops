terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Remote state for team use. Create the bucket/table once, then uncomment and run `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket         = "nexvion-terraform-state"
  #   key            = "ai-ecommerce-devops/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "nexvion-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
