# ==============================================================
# MÓDULO SECURITY GROUPS
# Os SGs são criados primeiro SEM as regras que cruzam referências,
# depois as regras são adicionadas via aws_security_group_rule.
# Isso elimina o ciclo de dependência circular.
# ==============================================================

# --------------------------------------------------------------
# SG — ALB (apenas declaração — regras cruzadas abaixo)
# --------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-sg-alb"
  description = "Security Group do ALB - aceita trafego publico HTTP/HTTPS"
  vpc_id      = var.vpc_id

  # Entrada HTTP público
  ingress {
    description = "HTTP de qualquer origem"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Entrada HTTPS público
  ingress {
    description = "HTTPS de qualquer origem"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------
# SG — Aplicação (criado sem regras que referenciam ALB/DB)
# --------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-sg-app"
  description = "Security Group da aplicacao - trafego apenas do ALB"
  vpc_id      = var.vpc_id

  # Saída HTTPS para internet (APIs externas, atualizações)
  egress {
    description = "HTTPS para internet via NAT ou VPC Endpoint"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída HTTP para internet
  egress {
    description = "HTTP para internet via NAT"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-app"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------
# SG — Banco de Dados (criado sem regras que referenciam App)
# --------------------------------------------------------------
resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-sg-database"
  description = "Security Group do banco - PostgreSQL apenas da aplicacao"
  vpc_id      = var.vpc_id

  # Saída restrita ao CIDR interno
  egress {
    description = "Respostas internas VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------------------
# SG — Bastion Host
# --------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-${var.environment}-sg-bastion"
  description = "Security Group do bastion - SSH restrito por IP"
  vpc_id      = var.vpc_id

  # Entrada SSH — apenas IPs autorizados
  ingress {
    description = "SSH apenas dos IPs autorizados"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
  }

  # Saída SSH para instâncias privadas
  egress {
    description = "SSH para instancias privadas da VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-bastion"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================
# REGRAS CRUZADAS — adicionadas após todos os SGs estarem criados
# Isso quebra o ciclo de dependência circular.
# ==============================================================

# ALB → App (saída do ALB para a porta da aplicação)
resource "aws_security_group_rule" "alb_egress_to_app" {
  type                     = "egress"
  description              = "ALB encaminha para a aplicacao"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = aws_security_group.app.id
}

# App ← ALB (entrada na porta da aplicação apenas do ALB)
resource "aws_security_group_rule" "app_ingress_from_alb" {
  type                     = "ingress"
  description              = "Porta da aplicacao apenas do ALB"
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.alb.id
}

# App → Database (saída da app para PostgreSQL)
resource "aws_security_group_rule" "app_egress_to_db" {
  type                     = "egress"
  description              = "PostgreSQL apenas para o banco"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.app.id
  source_security_group_id = aws_security_group.database.id
}

# Database ← App (entrada PostgreSQL apenas da app)
resource "aws_security_group_rule" "db_ingress_from_app" {
  type                     = "ingress"
  description              = "PostgreSQL apenas da aplicacao"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.database.id
  source_security_group_id = aws_security_group.app.id
}

# Bastion → Database (acesso DBA direto ao banco)
resource "aws_security_group_rule" "bastion_egress_to_db" {
  type                     = "egress"
  description              = "PostgreSQL DBA do bastion para o banco"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.bastion.id
  source_security_group_id = aws_security_group.database.id
}
