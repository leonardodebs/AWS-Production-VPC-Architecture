output "vpc_id" {
  description = "ID da VPC — referenciado por todos os recursos na VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block da VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas (para ALB, NAT Gateways, Bastion)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas (para EC2, ECS, EKS nodes)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs das subnets de banco (para RDS Multi-AZ)"
  value       = aws_subnet.database[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs alocados aos NAT Gateways (útil para whitelisting)"
  value       = aws_eip.nat[*].public_ip
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways"
  value       = aws_nat_gateway.this[*].id
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "ID da route table pública"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "IDs das route tables privadas (1 por AZ)"
  value       = aws_route_table.private[*].id
}

output "db_subnet_group_name" {
  description = "Nome do DB Subnet Group — requerido para criar instâncias RDS"
  value       = aws_db_subnet_group.this.name
}

output "db_subnet_group_id" {
  description = "ID do DB Subnet Group"
  value       = aws_db_subnet_group.this.id
}

output "vpc_endpoint_s3_id" {
  description = "ID do VPC Endpoint para S3"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.s3[0].id : null
}

output "vpc_endpoint_dynamodb_id" {
  description = "ID do VPC Endpoint para DynamoDB"
  value       = var.enable_vpc_endpoints ? aws_vpc_endpoint.dynamodb[0].id : null
}
