output "alb_sg_id" {
  description = "ID do Security Group do ALB"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "ID do Security Group da aplicação"
  value       = aws_security_group.app.id
}

output "database_sg_id" {
  description = "ID do Security Group do banco de dados"
  value       = aws_security_group.database.id
}

output "bastion_sg_id" {
  description = "ID do Security Group do bastion host"
  value       = aws_security_group.bastion.id
}
