# ============================================================
# Outputs do ambiente dev — consumidos por outros projetos
# ============================================================

output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block da VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (ALB, NAT Gateways)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (instâncias de aplicação)"
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "IDs das subnets de banco de dados"
  value       = module.vpc.database_subnet_ids
}

output "nat_public_ips" {
  description = "Elastic IPs dos NAT Gateways"
  value       = module.vpc.nat_public_ips
}

output "db_subnet_group_name" {
  description = "Nome do DB Subnet Group para uso no RDS (Projeto 03)"
  value       = module.vpc.db_subnet_group_name
}

output "alb_sg_id" {
  description = "ID do Security Group do ALB"
  value       = module.security_groups.alb_sg_id
}

output "app_sg_id" {
  description = "ID do Security Group da aplicação"
  value       = module.security_groups.app_sg_id
}

output "database_sg_id" {
  description = "ID do Security Group do banco de dados"
  value       = module.security_groups.database_sg_id
}

output "bastion_sg_id" {
  description = "ID do Security Group do bastion host"
  value       = module.security_groups.bastion_sg_id
}

output "flow_log_group_name" {
  description = "Nome do CloudWatch Log Group dos Flow Logs"
  value       = module.flow_logs.log_group_name
}
