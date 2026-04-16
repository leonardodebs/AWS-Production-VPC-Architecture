output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR da VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs subnets publicas"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs subnets privadas"
  value       = module.vpc.private_subnet_ids
}

output "database_subnet_ids" {
  description = "IDs subnets banco"
  value       = module.vpc.database_subnet_ids
}

output "nat_public_ips" {
  description = "Elastic IPs dos NATs"
  value       = module.vpc.nat_public_ips
}

output "db_subnet_group_name" {
  description = "DB Subnet Group do RDS"
  value       = module.vpc.db_subnet_group_name
}

output "alb_sg_id" {
  description = "SG do ALB"
  value       = module.security_groups.alb_sg_id
}

output "app_sg_id" {
  description = "SG da aplicacao"
  value       = module.security_groups.app_sg_id
}

output "database_sg_id" {
  description = "SG do banco"
  value       = module.security_groups.database_sg_id
}

output "bastion_sg_id" {
  description = "SG do bastion"
  value       = module.security_groups.bastion_sg_id
}

output "flow_log_group_name" {
  description = "CloudWatch Log Group"
  value       = module.flow_logs.log_group_name
}
