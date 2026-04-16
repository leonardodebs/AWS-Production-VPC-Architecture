output "flow_log_id" {
  description = "ID do VPC Flow Log"
  value       = aws_flow_log.this.id
}

output "log_group_name" {
  description = "Nome do CloudWatch Log Group que armazena os flow logs"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "log_group_arn" {
  description = "ARN do CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.flow_logs.arn
}

output "iam_role_arn" {
  description = "ARN da IAM Role usada pelo Flow Log"
  value       = aws_iam_role.flow_logs.arn
}
