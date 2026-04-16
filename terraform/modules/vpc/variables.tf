variable "project_name" {
  description = "Nome do projeto — prefixo de todos os recursos"
  type        = string
}

variable "environment" {
  description = "Ambiente de implantação: dev, staging ou prod"
  type        = string
}

variable "aws_region" {
  description = "Região AWS (necessária para os endpoints)"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block principal da VPC (ex: 10.0.0.0/16)"
  type        = string
}

variable "azs" {
  description = "Lista de Availability Zones onde os recursos serão distribuídos"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas — 1 por AZ, usadas por ALB e NAT Gateways"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas — 1 por AZ, usadas por instâncias de aplicação"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDRs das subnets de banco de dados — 1 por AZ, sem rota para internet"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Usar apenas um NAT Gateway para todas as subnets privadas (economia)"
  type        = bool
  default     = true
}

variable "enable_nat_instance" {
  description = "Usar uma instancia EC2 (t3.nano) como NAT em vez do NAT Gateway gerenciado (muito mais barato)"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Cria VPC Gateway Endpoints para S3 e DynamoDB (gratuitos)"
  type        = bool
  default     = true
}
