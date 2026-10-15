# ---- アクセスログ用バケット（ELB.5） ----
resource "aws_s3_bucket" "alb_logs" {
  bucket_prefix = "${var.name}-alb-logs-"
  # 検証環境のため destroy 時にログごと削除する
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ALB のアクセスログは SSE-S3 のみ対応
resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowELBLogDelivery"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.alb_logs.arn, "${aws_s3_bucket.alb_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# ---- ALB ----
resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  subnets                    = aws_subnet.public[*].id
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true                           # ELB.4
  enable_deletion_protection = var.enable_deletion_protection # ELB.6

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

# Blue / Green 用の 2 つのターゲットグループ
resource "aws_lb_target_group" "this" {
  for_each = toset(["blue", "green"])

  name                 = "${var.name}-${each.key}"
  port                 = var.container_port
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
