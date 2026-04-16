# ==============================================================
# MÓDULO VPC
# Provisiona: VPC, subnets (pública/privada/banco), IGW,
# NAT Gateways, Elastic IPs, Route Tables, NACLs,
# VPC Endpoints (S3 e DynamoDB), DB Subnet Group.
# ==============================================================

# --------------------------------------------------------------
# VPC e Internet Gateway
# --------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# --------------------------------------------------------------
# Subnets Públicas — 1 por AZ
# Usadas por: ALB, NAT Gateways, Bastion Host
# --------------------------------------------------------------
resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # Instâncias públicas recebem IP público automaticamente
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${count.index + 1}"
    tipo = "publica"
  }
}

# --------------------------------------------------------------
# Subnets Privadas — 1 por AZ
# Usadas por: instâncias de aplicação (EC2, ECS, EKS nodes)
# Saída via NAT Gateway
# --------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${count.index + 1}"
    tipo = "privada"
    # Tags necessárias para EKS (Projeto 07)
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# --------------------------------------------------------------
# Subnets de Banco de Dados — 1 por AZ
# SEM rota de saída para internet — isolamento máximo
# Usadas por: RDS Multi-AZ
# --------------------------------------------------------------
resource "aws_subnet" "database" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-${var.environment}-database-${count.index + 1}"
    tipo = "banco"
  }
}

# --------------------------------------------------------------
# DB Subnet Group — necessário para provisionar RDS Multi-AZ
# --------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "DB Subnet Group para ${var.project_name}-${var.environment}"
  subnet_ids  = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# --------------------------------------------------------------
# Elastic IPs para NAT Gateways
# Quantidade: 1 (single_nat=true) ou 1 por AZ (single_nat=false)
# --------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : length(var.azs)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

# --------------------------------------------------------------
# NAT Gateways — sempre em subnets públicas
# Dev/Staging: 1 compartilhado (economia de custo)
# Prod: 1 por AZ (Alta Disponibilidade)
# --------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  count         = (!var.enable_nat_instance) ? (var.single_nat_gateway ? 1 : length(var.azs)) : 0
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

# --------------------------------------------------------------
# NAT Instance (EC2) — Alternativa de baixo custo ao NAT Gateway
# Criada apenas se enable_nat_instance for true.
# --------------------------------------------------------------
resource "aws_security_group" "nat" {
  count       = var.enable_nat_instance ? 1 : 0
  name        = "${var.project_name}-${var.environment}-sg-nat"
  description = "Security Group para NAT Instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Permite todo trafego da VPC para roteamento"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Saida para internet"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-nat"
  }
}

resource "aws_instance" "nat" {
  count                  = var.enable_nat_instance ? 1 : 0
  ami                    = data.aws_ssm_parameter.ami_linux_2023.value
  instance_type          = "t3.nano"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.nat[0].id]
  source_dest_check      = false # CRITICO para NAT

  user_data = <<-EOF
              #!/bin/bash
              # Habilita IP Forwarding no kernel
              echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
              sysctl -p
              # Configura IP Masquerade (iptables)
              dnf install -y iptables-services
              systemctl enable iptables
              systemctl start iptables
              iptables -t nat -A POSTROUTING -o $(ip -o -4 route show to default | awk '{print $5}') -j MASQUERADE
              /sbin/iptables-save > /etc/sysconfig/iptables
              EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-instance"
  }
}

# --------------------------------------------------------------
# Route Table Pública — rota padrão via IGW
# Uma única RT compartilhada por todas as subnets públicas.
# --------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-public"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --------------------------------------------------------------
# Route Tables Privadas — rota padrão via NAT Gateway
# Dev/Staging: todas as subnets privadas usam o mesmo NAT
# Prod: cada AZ tem sua própria RT apontando para seu NAT
# --------------------------------------------------------------
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block           = "0.0.0.0/0"
    nat_gateway_id       = (!var.enable_nat_instance) ? (var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id) : null
    network_interface_id = var.enable_nat_instance ? aws_instance.nat[0].primary_network_interface_id : null
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-private-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --------------------------------------------------------------
# Route Tables de Banco — SEM rota de saída (isolamento total)
# Apenas tráfego interno à VPC é permitido.
# --------------------------------------------------------------
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  # Sem rota 0.0.0.0/0 — acesso externo bloqueado

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-database"
  }
}

resource "aws_route_table_association" "database" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# ==============================================================
# NETWORK ACLs
# ==============================================================

# --------------------------------------------------------------
# NACL — Subnets Públicas
# Stateless: requer regras de entrada E saída
# Permite: HTTP(80), HTTPS(443), portas efêmeras (resposta TCP)
# --------------------------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  # --- INGRESS ---
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Portas efêmeras — necessárias para respostas das conexões saintes
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # DENY implícito para todo o resto

  # --- EGRESS ---
  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nacl-public"
  }
}

# --------------------------------------------------------------
# NACL — Subnets Privadas
# Permite: tráfego interno da VPC + efêmeras para respostas
# Bloqueia: qualquer tráfego direto da internet
# --------------------------------------------------------------
resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id

  # Permite tráfego interno da VPC
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  # Portas efêmeras para respostas de conexões saintes (NAT → internet)
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nacl-private"
  }
}

# --------------------------------------------------------------
# NACL — Subnets de Banco
# Restrição máxima: apenas porta 5432 do CIDR das subnets privadas
# --------------------------------------------------------------
resource "aws_network_acl" "database" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.database[*].id

  # Permite PostgreSQL apenas das subnets privadas (app)
  dynamic "ingress" {
    for_each = var.private_subnet_cidrs
    content {
      protocol   = "tcp"
      rule_no    = 100 + ingress.key * 10
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 5432
      to_port    = 5432
    }
  }

  # Portas efêmeras para respostas
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nacl-database"
  }
}

# ==============================================================
# VPC ENDPOINTS — Gateway type (gratuitos)
# Tráfego para S3 e DynamoDB não passa pelo NAT Gateway
# ==============================================================
resource "aws_vpc_endpoint" "s3" {
  count        = var.enable_vpc_endpoints ? 1 : 0
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.aws_region}.s3"

  # Associa a todas as route tables (pública + privadas)
  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-s3"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  count        = var.enable_vpc_endpoints ? 1 : 0
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id,
    [aws_route_table.database.id]
  )

  tags = {
    Name = "${var.project_name}-${var.environment}-vpce-dynamodb"
  }
}
