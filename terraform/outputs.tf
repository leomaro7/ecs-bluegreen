output "prod_url" {
  value = "http://${aws_lb.this.dns_name}"
}

output "test_url" {
  value = "http://${aws_lb.this.dns_name}:8080"
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}
