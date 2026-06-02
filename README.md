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
