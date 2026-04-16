# ============================================================
# Variáveis comuns a todos os ambientes
# ============================================================

variable "project_name" {
  description = "Nome do projeto — usado como prefixo em todos os recursos"
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
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-west-2"
}

# ============================================================
# Variáveis de rede
# ============================================================

variable "vpc_cidr" {
  description = "CIDR block principal da VPC"
  type        = string
}

variable "azs" {
  description = "Lista de Availability Zones para distribuição dos recursos"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs das subnets públicas (ALB, NAT Gateways)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs das subnets privadas (instâncias de aplicação)"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDRs das subnets de banco de dados (sem rota para internet)"
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
  description = "Cria VPC Endpoints Gateway para S3 e DynamoDB (gratuitos)"
  type        = bool
  default     = true
}

# ============================================================
# Variáveis de Flow Logs
# ============================================================

variable "flow_log_traffic_type" {
  description = "Tipo de tráfego capturado: ACCEPT, REJECT ou ALL"
  type        = string
  default     = "REJECT"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type deve ser ACCEPT, REJECT ou ALL."
  }
}

variable "flow_log_retention_days" {
  description = "Retenção dos logs no CloudWatch em dias"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 180, 365], var.flow_log_retention_days)
    error_message = "flow_log_retention_days deve ser um valor válido do CloudWatch."
  }
}

# ============================================================
# Variáveis de Security Groups
# ============================================================

variable "app_port" {
  description = "Porta TCP da aplicação (tráfego ALB → App)"
  type        = number
  default     = 8080
}

variable "bastion_allowed_cidrs" {
  description = "Lista de CIDRs autorizados a acessar o bastion host via SSH"
  type        = list(string)

  validation {
    condition     = length(var.bastion_allowed_cidrs) > 0
    error_message = "Informe pelo menos 1 CIDR para acesso ao bastion. Use seu IP: curl ifconfig.me"
  }
}
