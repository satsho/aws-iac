provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "satsho/aws-iac"
    }
  }
}