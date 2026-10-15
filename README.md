# ecs-bluegreen

ECS Fargate のネイティブ Blue/Green デプロイ（`deploymentConfiguration.strategy = BLUE_GREEN`）を、GitHub Actions と Terraform で組むサンプルです。CodeDeploy は使いません。

- `terraform/` … VPC / ALB（本番 :80・テスト :8080、TG blue/green）/ ECR / ECS / IAM（GitHub OIDC）
- `.github/workflows/deploy.yml` … build → ECR push → タスク定義の差し替え → `UpdateService`
- `app/` … 非 root・読み取り専用ルートで動く nginx

手順は Qiita の記事を参照してください。

## 後片付け

```bash
cd terraform
terraform apply -var enable_deletion_protection=false
terraform destroy -var enable_deletion_protection=false
aws logs delete-log-group --log-group-name /aws/ecs/containerinsights/ecs-bluegreen/performance
```
