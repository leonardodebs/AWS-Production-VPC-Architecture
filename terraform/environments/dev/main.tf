terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto S3 — para uso com AWS real.
  # Para testes locais, use: powershell scripts\test-local.ps1
  # Substitua SEU-ACCOUNT-ID pelo valor de:
  #   aws sts get-caller-identity --query Account --output text
  backend "s3" {
    bucket       = "terraform-state-SEU-ACCOUNT-ID-us-west-2"
    key          = "dev/vpc/terraform.tfstate"
    region       = "us-west-2"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      gerenciado-por = "terraform"
      projeto        = var.project_name
      ambiente       = var.environment
    }
  }
}

# =============================================================
# MÓDULO VPC — Rede, subnets, IGW, NAT, route tables, NACLs, endpoints
# =============================================================
module "vpc" {
  source = "../../modules/vpc"

  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  azs                   = var.azs
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  single_nat_gateway    = var.single_nat_gateway
  enable_nat_instance   = var.enable_nat_instance
  enable_vpc_endpoints  = var.enable_vpc_endpoints
}

# =============================================================
# MÓDULO SECURITY GROUPS — ALB, app, banco, bastion
# =============================================================
module "security_groups" {
  source = "../../modules/security-groups"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  app_port              = var.app_port
  bastion_allowed_cidrs = var.bastion_allowed_cidrs
}

# =============================================================
# MÓDULO FLOW LOGS — VPC Flow Logs → CloudWatch
# =============================================================
module "flow_logs" {
  source = "../../modules/flow-logs"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = module.vpc.vpc_id
  flow_log_traffic_type   = var.flow_log_traffic_type
  flow_log_retention_days = var.flow_log_retention_days
}
