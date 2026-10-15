variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "name" {
  type    = string
  default = "ecs-bluegreen"
}

variable "github_owner" {
  type        = string
  description = "GitHub のユーザー名 / Organization 名"
}

variable "github_repo" {
  type        = string
  description = "GitHub のリポジトリ名"
}

variable "github_owner_id" {
  type        = string
  description = "gh api repos/<owner>/<repo> --jq .owner.id"
}

variable "github_repo_id" {
  type        = string
  description = "gh api repos/<owner>/<repo> --jq .id"
}

variable "test_listener_cidr" {
  type        = string
  description = "テストリスナー(8080)へのアクセスを許可する CIDR"
}

variable "bake_time_in_minutes" {
  type    = number
  default = 3
}
