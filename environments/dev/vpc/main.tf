# dev 環境の VPC サービス。サービス単位の root = 独立した state を持つ。

terraform {
  required_version = ">= 1.6"

  # ↓ bucket は bootstrap の出力(state_bucket)に手で置き換える。
  backend "s3" {
    bucket         = "REPLACE-WITH-STATE-BUCKET"
    key            = "dev/vpc/terraform.tfstate" # サービスごとに key を分ける
    region         = "ap-northeast-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = "ap-northeast-1"
}

module "vpc" {
  source = "../../../modules/vpc" # 1階層深くなったので ../ が3つ

  name = "dev"
  # cidr_block は当面モジュール既定(10.0.0.0/16)を使用。IP 設計時に明示。
  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
