# ---- アプリのリポジトリ（ECR.1 / ECR.2 / ECR.3） ----
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ---- ECS ----
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 30
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights" # ECS.12
    value = "enhanced"
  }
}

# 初回だけ Terraform で登録する枠。desired_count = 0 で作るのでこのリビジョンは起動しない。
# 最初の push で GitHub Actions が自前イメージのリビジョンを登録してタスク数を上げる
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  # 読み取り専用ルートでも nginx が pid / 一時ファイルを書けるようにする
  volume {
    name = "tmp"
  }

  container_definitions = jsonencode([{
    name                   = "app"
    image                  = "${aws_ecr_repository.this.repository_url}:bootstrap"
    essential              = true
    user                   = "101"
    readonlyRootFilesystem = true # ECS.5
    privileged             = false
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    mountPoints = [{
      sourceVolume  = "tmp"
      containerPath = "/tmp"
      readOnly      = false
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name                   = var.name
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this.arn
  desired_count          = 0
  launch_type            = "FARGATE"
  platform_version       = "LATEST"
  enable_execute_command = false
  propagate_tags         = "SERVICE"

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = var.bake_time_in_minutes
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this["blue"].arn
    container_name   = "app"
    container_port   = var.container_port

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.this["green"].arn
      production_listener_rule   = aws_lb_listener_rule.this["prod"].arn
      test_listener_rule         = aws_lb_listener_rule.this["test"].arn
      role_arn                   = aws_iam_role.ecs_infra_lb.arn
    }
  }

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false # ECS.2
  }

  # task_definition と desired_count は GitHub Actions が更新し、
  # load_balancer の primary / alternate はデプロイごとに ECS が入れ替える
  lifecycle {
    ignore_changes = [task_definition, desired_count, load_balancer]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_infra_lb,
    aws_lb_listener_rule.this,
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
  ]
}
