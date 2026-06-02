#!/usr/bin/env bash
#
# aws-iac の中身を「カレントディレクトリ」に展開するセットアップスクリプト
# 前提: すでに aws-iac リポジトリを作成し、その中で実行する
# 使い方:
#   cd aws-iac
#   bash setup-aws-iac.sh           # カレント(=aws-iac直下)に配置
#   bash setup-aws-iac.sh path/to   # 別ディレクトリ配下に配置したい場合
set -euo pipefail
ROOT="${1:-.}"
echo "==> creating under: $ROOT"

mkdir -p "$ROOT/.github/workflows"
cat > "$ROOT/.github/workflows/apply.yml" << '__AWS_IAC_EOF__'
name: Terraform Apply

# main にマージされたら apply を実行し、実際に VPC+IGW を作成/更新する。

on:
  push:
    branches: [main]
    paths:
      - "environments/dev/vpc/**"
      - "modules/vpc/**"

permissions:
  id-token: write
  contents: read

jobs:
  apply:
    uses: ./.github/workflows/terraform.yml
    with:
      working-directory: environments/dev/vpc
      command: apply
    secrets:
      role-arn: ${{ secrets.TF_ROLE_ARN }}
__AWS_IAC_EOF__

mkdir -p "$ROOT/.github/workflows"
cat > "$ROOT/.github/workflows/plan.yml" << '__AWS_IAC_EOF__'
name: Terraform Plan

# PR が作られたら plan を実行し、差分をレビュー材料にする。

on:
  pull_request:
    paths:
      - "environments/dev/vpc/**"
      - "modules/vpc/**"

permissions:
  id-token: write
  contents: read

jobs:
  plan:
    uses: ./.github/workflows/terraform.yml
    with:
      working-directory: environments/dev/vpc
      command: plan
    secrets:
      role-arn: ${{ secrets.TF_ROLE_ARN }}
__AWS_IAC_EOF__

mkdir -p "$ROOT/.github/workflows"
cat > "$ROOT/.github/workflows/terraform.yml" << '__AWS_IAC_EOF__'
name: Terraform (reusable)

# plan と apply を共通化した唯一の実行ロジック（= Reusable Workflow によるモジュール化）。
# 呼び出し側(plan.yml / apply.yml)が command を渡して使い分ける。

on:
  workflow_call:
    inputs:
      working-directory:
        required: true
        type: string
      command:
        description: "plan または apply"
        required: true
        type: string
      aws-region:
        required: false
        type: string
        default: ap-northeast-1
    secrets:
      role-arn:
        required: true

permissions:
  id-token: write # OIDC に必須
  contents: read

jobs:
  terraform:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ inputs.working-directory }}
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.6

      - name: AWS 認証（OIDC・長期キー不使用）
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.role-arn }}
          aws-region: ${{ inputs.aws-region }}

      - name: init
        run: terraform init -input=false

      - name: fmt & validate
        run: |
          terraform fmt -check -recursive
          terraform validate

      - name: plan
        if: inputs.command == 'plan'
        run: terraform plan -input=false

      - name: apply
        if: inputs.command == 'apply'
        run: terraform apply -input=false -auto-approve
__AWS_IAC_EOF__

mkdir -p "$ROOT/."
cat > "$ROOT/README.md" << '__AWS_IAC_EOF__'
# aws-iac — AWS リソース作成パイプライン(GitHub Actions × Terraform)

GitHub Actions と Terraform を両方モジュール化し、AWS リソースを定型的に作成する器(モノレポ)。
第一弾として VPC + IGW を扱う。サービスを足すたびにこのリポジトリに追加していく。
IP 設計(サブネット CIDR 等)とセキュリティ強制は **今回スコープ外**。

## 構成

| 項目 | 内容 |
|---|---|
| リポジトリ | モノレポ `aws-iac` |
| デプロイ単位 | サービスごとに独立 state(案B) |
| 環境 | dev 1つ |
| 作るもの | VPC + IGW(NAT なし=コスト$0) |
| CI | PR で plan / main マージで自動 apply |
| モジュール参照 | ローカルパス |
| 認証 | GitHub OIDC(長期キー不使用) |
| リージョン | ap-northeast-1(東京) |

## ディレクトリ

```
aws-iac/
├── bootstrap/                      # Phase0: 一度きり・ローカルapply
│   ├── main.tf                     #   state基盤(S3+DynamoDB) + OIDC + ロール
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── modules/                        # 再利用可能な部品（サービスごと）
│   └── vpc/                        #   VPC + IGW
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   └── dev/
│       └── vpc/                    # サービス単位の root = 独立 state
│           └── main.tf             #   modules/vpc をローカルパス参照
└── .github/workflows/
    ├── terraform.yml               # Reusable Workflow（plan/apply共通ロジック）
    ├── plan.yml                    # PR で plan
    └── apply.yml                   # main マージで apply
```

## 手順

### Phase 0 — bootstrap(一度きり・ローカル実行)

1. このリポジトリ(`aws-iac`)を作成し、ファイル一式を配置。
2. `bootstrap/terraform.tfvars.example` を `terraform.tfvars` にコピーして値を設定。
3. ローカルの admin 認証で実行:
   ```bash
   cd bootstrap
   terraform init
   terraform apply
   ```
   → S3 / DynamoDB / OIDCプロバイダ / IAMロールが作られる。出力 `role_arn` と `state_bucket` を控える。
4. GitHub の Settings → Secrets → Actions に `TF_ROLE_ARN`(= `role_arn`)を登録。
5. `environments/dev/vpc/main.tf` の backend の `bucket` を、出力された `state_bucket` に置き換える。

### Phase 1 — 通常運用

6. ブランチを切って `environments/dev/vpc/` か `modules/vpc/` を変更 → **PR 作成**。→ `plan.yml` が plan を表示。
7. レビュー後に **main へマージ**。→ `apply.yml` が OIDC でロールを Assume し apply。VPC+IGW が作成される。

## 新しいサービスの足し方(例: S3)

1. `modules/s3/` に部品(モジュール)を作る。
2. `environments/dev/s3/main.tf` を作り、`source = "../../../modules/s3"` で参照。
   backend の `key` は `dev/s3/terraform.tfstate` のようにサービスごとに分ける。
3. `plan.yml` / `apply.yml` に S3 用の呼び出しを足す(または paths と working-directory を増やす)。
4. サービス間で値を渡したいとき(例: VPC の ID を S3 側で使う)は
   `terraform_remote_state` データソースで他サービスの state を参照する。

## 今回スコープ外(次の段階で対応)

- **IP 設計**: VPC の CIDR 確定、サブネット、ルートテーブル、(必要なら)NAT。
- **セキュリティ強制**: IAM ロール権限の最小化、plan / apply ロール分離、
  Environment 承認ゲート、Policy as Code、信頼ポリシーの sub / job_workflow_ref 絞り込み。

> 注: アカウントID・組織名・バケット名・各バージョンは例示。環境に合わせて置き換えること。
__AWS_IAC_EOF__

mkdir -p "$ROOT/bootstrap"
cat > "$ROOT/bootstrap/main.tf" << '__AWS_IAC_EOF__'
# Phase 0: bootstrap（一度きり・ローカルapply）
# backend を書かない = ローカルstate。一度きりの実行なのでこれでよい。
# state基盤 / OIDCプロバイダ / パイプライン用ロールを作る。

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ============ Terraform state 基盤 ============

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tflock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # 使った分だけ。ロック用途なら実質ほぼ無料
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

# ============ GitHub OIDC プロバイダ ============
# thumbprint は AWS が信頼済みCAで検証するため実質使われないが、
# 正しい値を動的取得しておくのが無難。
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# ============ パイプラインが Assume するロール ============
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # 当面はリポジトリ単位で許可。セキュリティを詰める段階で
    # ブランチや job_workflow_ref まで絞る。
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_owner}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "tf_pipeline" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

data "aws_iam_policy_document" "perms" {
  # VPC + IGW の作成に必要な EC2 権限（後でさらに絞る前提）
  statement {
    sid    = "VpcManage"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:Describe*",
    ]
    resources = ["*"]
  }
  # state 用 S3
  statement {
    sid       = "TfStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.tfstate.arn}/*"]
  }
  statement {
    sid       = "TfStateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.tfstate.arn]
  }
  # ロック用 DynamoDB
  statement {
    sid       = "TfLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tflock.arn]
  }
}

resource "aws_iam_role_policy" "tf_pipeline" {
  name   = "${var.role_name}-policy"
  role   = aws_iam_role.tf_pipeline.id
  policy = data.aws_iam_policy_document.perms.json
}
__AWS_IAC_EOF__

mkdir -p "$ROOT/bootstrap"
cat > "$ROOT/bootstrap/outputs.tf" << '__AWS_IAC_EOF__'
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
__AWS_IAC_EOF__

mkdir -p "$ROOT/bootstrap"
cat > "$ROOT/bootstrap/terraform.tfvars.example" << '__AWS_IAC_EOF__'
# cp して terraform.tfvars にリネームし、値を埋める
state_bucket_name = "sho-org-tfstate-XXXX" # グローバル一意にする
github_owner      = "sho-org"
github_repo       = "vpc-iac"
# region / lock_table_name / role_name は既定値でよければ省略可
__AWS_IAC_EOF__

mkdir -p "$ROOT/bootstrap"
cat > "$ROOT/bootstrap/variables.tf" << '__AWS_IAC_EOF__'
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
__AWS_IAC_EOF__

mkdir -p "$ROOT/environments/dev/vpc"
cat > "$ROOT/environments/dev/vpc/main.tf" << '__AWS_IAC_EOF__'
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
__AWS_IAC_EOF__

mkdir -p "$ROOT/modules/vpc"
cat > "$ROOT/modules/vpc/main.tf" << '__AWS_IAC_EOF__'
# VPC モジュール（VPC + IGW のみ。NAT なし=コスト$0）
# サブネットやルーティングは IP 設計の段階でこのモジュールに足していく。

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}
__AWS_IAC_EOF__

mkdir -p "$ROOT/modules/vpc"
cat > "$ROOT/modules/vpc/outputs.tf" << '__AWS_IAC_EOF__'
output "vpc_id" {
  description = "作成した VPC の ID"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC の CIDR"
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "Internet Gateway の ID"
  value       = aws_internet_gateway.this.id
}
__AWS_IAC_EOF__

mkdir -p "$ROOT/modules/vpc"
cat > "$ROOT/modules/vpc/variables.tf" << '__AWS_IAC_EOF__'
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
__AWS_IAC_EOF__

echo "==> done. created files:"
find "$ROOT" -type f -not -path "*/.git/*" | sort
