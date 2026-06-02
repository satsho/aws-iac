
terraform {
  required_version = ">= 1.6"

  backend "s3" {
    bucket         = "terraform-state-repo-satsho"
    key            = "dev/vpc/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source = "../../../modules/vpc"

  name = "dev"
  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
