output "state_bucket" {
  description = "environments/*/main.tf の backend に設定する S3 バケット名"
  value       = aws_s3_bucket.tfstate.bucket
}

output "lock_table" {
  description = "backend に設定する DynamoDB ロックテーブル名"
  value       = aws_dynamodb_table.tflock.name
}

output "role_arn" {
  description = "GitHub Secrets の TF_ROLE_ARN に登録する値"
  value       = aws_iam_role.tf_pipeline.arn
}
