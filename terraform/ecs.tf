resource "aws_ecr_repository" "this" {
  name         = var.name
  force_delete = true
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "this" {
  name = var.name
}

# 初回だけ Terraform で登録する。以降のリビジョンは GitHub Actions が登録する
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.task_execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = "public.ecr.aws/nginx/nginx:stable-alpine"
    essential = true
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
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
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

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
    container_port   = 80

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.this["green"].arn
      production_listener_rule   = aws_lb_listener_rule.this["prod"].arn
      test_listener_rule         = aws_lb_listener_rule.this["test"].arn
      role_arn                   = aws_iam_role.ecs_infra_lb.arn
    }
  }

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  # task_definition は GitHub Actions が更新し、
  # load_balancer の primary / alternate はデプロイごとに ECS が入れ替える
  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }

  depends_on = [
    aws_iam_role_policy_attachment.ecs_infra_lb,
    aws_lb_listener_rule.this,
  ]
}
