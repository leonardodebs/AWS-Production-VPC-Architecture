variable "project_name" {
  description = "Nome do projeto"
  type        = string
}

variable "environment" {
  description = "Ambiente de implantação"
  type        = string
}

variable "vpc_id" {
  description = "ID da VPC para capturar os flow logs"
  type        = string
}

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
}
