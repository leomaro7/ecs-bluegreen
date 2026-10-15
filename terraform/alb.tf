resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = aws_subnet.public[*].id
  security_groups    = [aws_security_group.alb.id]
}

# Blue / Green 用の 2 つのターゲットグループ
resource "aws_lb_target_group" "this" {
  for_each = toset(["blue", "green"])

  name                 = "${var.name}-${each.key}"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.this.id
  deregistration_delay = 10

  health_check {
    path                = "/"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# 本番リスナー(80) と テストリスナー(8080)
resource "aws_lb_listener" "this" {
  for_each = { prod = 80, test = 8080 }

  load_balancer_arn = aws_lb.this.arn
  port              = each.value
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "not found"
      status_code  = "404"
    }
  }
}

# ECS が重みを書き換えるリスナールール（blue:100 / green:0 で開始）
resource "aws_lb_listener_rule" "this" {
  for_each = aws_lb_listener.this

  listener_arn = each.value.arn
  priority     = 1

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.this["blue"].arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.this["green"].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  # デプロイのたびに ECS が重みを入れ替えるので Terraform では追従しない
  lifecycle {
    ignore_changes = [action]
  }
}
