variable "name" {
  type        = string
  description = "VPC の名前（Name タグに使用）"
}

variable "cidr_block" {
  type        = string
  description = "VPC の CIDR。IP 設計の段階で確定する想定。"
  default     = "10.0.0.0/16" # 仮値。後で見直す。
}

variable "tags" {
  type        = map(string)
  description = "共通タグ"
  default     = {}
}
