terraform {
  backend "s3" {
    bucket       = "terraform-state-repo-satsho"
    key          = "iam/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true          # Terraform 1.10+ の S3 ネイティブロック
    encrypt      = true
  }
}