# ==============================================================
# MÓDULO FLOW LOGS
# Provisiona: IAM Role, CloudWatch Log Group, VPC Flow Log
# Os logs registram o tráfego de rede aceito/rejeitado na VPC
# para fins de auditoria, segurança e conformidade.
# ==============================================================

# --------------------------------------------------------------
# IAM Role — permite ao serviço VPC Flow Logs gravar no CloudWatch
# --------------------------------------------------------------
resource "aws_iam_role" "flow_logs" {
  name        = "${var.project_name}-${var.environment}-flow-logs-role"
  description = "IAM Role para VPC Flow Logs gravar no CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-logs-role"
  }
}

# --------------------------------------------------------------
# IAM Policy — permissões mínimas para gravar logs (least privilege)
# --------------------------------------------------------------
resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-${var.environment}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      }
    ]
  })
}

# --------------------------------------------------------------
# CloudWatch Log Group — destino dos Flow Logs
# Retenção configurável por ambiente:
#   dev/staging: 7 dias | prod: 90 dias
# --------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/vpc/${var.project_name}-${var.environment}-flow-logs"
  retention_in_days = var.flow_log_retention_days

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-logs"
  }
}

# --------------------------------------------------------------
# VPC Flow Log — captura tráfego de rede da VPC
# traffic_type:
#   REJECT  — apenas tráfego bloqueado (dev/staging — menor volume)
#   ALL     — todo o tráfego (prod — conformidade PCI-DSS, SOC 2)
# --------------------------------------------------------------
resource "aws_flow_log" "this" {
  vpc_id          = var.vpc_id
  traffic_type    = var.flow_log_traffic_type
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-flow-log"
  }
}
