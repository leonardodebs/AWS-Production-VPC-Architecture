variable "project_name" {
  description = "Nome do projeto — usado no prefixo dos SGs"
  type        = string
}

variable "environment" {
  description = "Ambiente de implantação"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC onde os Security Groups serão criados"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block da VPC — usado nas regras de saída restritas"
  type        = string
}

variable "app_port" {
  description = "Porta TCP da aplicação (tráfego ALB → App)"
  type        = number
  default     = 8080
}

variable "bastion_allowed_cidrs" {
  description = "Lista de CIDRs com permissão de acesso SSH ao bastion (ex: ['SEU_IP/32'])"
  type        = list(string)
}
