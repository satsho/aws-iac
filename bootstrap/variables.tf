variable "region" {
  type        = string
  description = "リソースを作るリージョン"
  default     = "ap-northeast-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Terraform state を置く S3 バケット名（グローバルで一意にすること）"
}

variable "lock_table_name" {
  type        = string
  description = "state ロック用 DynamoDB テーブル名"
  default     = "tfstate-lock"
}

variable "github_owner" {
  type        = string
  description = "GitHub の owner（例: sho-org）"
}

variable "github_repo" {
  type        = string
  description = "対象リポジトリ名（例: vpc-iac）"
}

variable "role_name" {
  type        = string
  description = "パイプラインが Assume する IAM ロール名"
  default     = "github-actions-tf"
}
