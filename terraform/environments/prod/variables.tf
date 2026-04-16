variable "project_name" {
  description = "Nome do projeto"
  type        = string
  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 16
    error_message = "project_name deve ter entre 1 e 16 caracteres."
  }
}
variable "environment" {
  description = "Ambiente de implantação"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment deve ser dev, staging ou prod."
  }
}
variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-west-2"
}
variable "vpc_cidr" {
  description = "CIDR block principal da VPC"
  type        = string
}
variable "azs" {
  description = "Lista de Availability Zones"
  type        = list(string)
}
variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas"
  type        = list(string)
}
variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas"
  type        = list(string)
}
variable "database_subnet_cidrs" {
  description = "CIDRs das subnets de banco de dados"
  type        = list(string)
}
variable "single_nat_gateway" {
  description = "Usar apenas um NAT Gateway para todas as subnets privadas"
  type        = bool
}

variable "enable_nat_instance" {
  description = "Usar uma instancia EC2 como NAT (muito mais barato que o NAT Gateway)"
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Cria VPC Endpoints para S3 e DynamoDB"
  type        = bool
  default     = true
}
variable "flow_log_traffic_type" {
  description = "Tipo de tráfego: ACCEPT, REJECT ou ALL"
  type        = string
  default     = "ALL"
  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type deve ser ACCEPT, REJECT ou ALL."
  }
}
variable "flow_log_retention_days" {
  description = "Retenção dos logs no CloudWatch em dias"
  type        = number
  default     = 90
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 180, 365], var.flow_log_retention_days)
    error_message = "flow_log_retention_days deve ser um valor válido do CloudWatch."
  }
}
variable "app_port" {
  description = "Porta TCP da aplicação"
  type        = number
  default     = 8080
}
variable "bastion_allowed_cidrs" {
  description = "CIDRs com acesso SSH ao bastion"
  type        = list(string)
  validation {
    condition     = length(var.bastion_allowed_cidrs) > 0
    error_message = "Informe pelo menos 1 CIDR para o bastion."
  }
}
