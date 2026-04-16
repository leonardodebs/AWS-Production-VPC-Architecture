# Variáveis de Ambiente — AWS Production VPC Architecture

> Template de configuração para todos os ambientes do projeto.  
> Copie o bloco do ambiente desejado para o arquivo `terraform.tfvars` correspondente.  
> **Nunca commite credenciais AWS** nestes arquivos. Use variáveis de ambiente do sistema ou AWS CLI.

---

## 📁 Estrutura de arquivos

```
terraform/
└── environments/
    ├── dev/
    │   ├── terraform.tfvars          ← copiar do bloco DEV abaixo
    │   └── backend.tfvars            ← configuração do remote state
    ├── staging/
    │   ├── terraform.tfvars          ← copiar do bloco STAGING abaixo
    │   └── backend.tfvars
    └── prod/
        ├── terraform.tfvars          ← copiar do bloco PROD abaixo
        └── backend.tfvars
```

---

## 🔐 Credenciais AWS — Configuração via CLI (recomendado)

Nunca coloque credenciais em arquivos `.tf` ou `.tfvars`. Use o AWS CLI:

```bash
# Configurar o perfil padrão
aws configure

# Verificar identidade antes de qualquer apply
aws sts get-caller-identity
```

**Saída esperada:**
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/seu-usuario"
}
```

**Alternativa: variáveis de ambiente do sistema (para CI/CD)**

```bash
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-west-2"
```

> ⚠️ Em pipelines CI/CD (GitHub Actions), use **Secrets** do repositório, nunca variáveis em texto claro.

---

## 🌐 Backend do Remote State

Crie o arquivo `backend.tfvars` em cada ambiente com o nome real do bucket:

```bash
# Descobrir o nome do bucket (se já foi criado)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "terraform-state-${ACCOUNT_ID}-us-west-2"
```

### `terraform/environments/dev/backend.tfvars`

```hcl
bucket         = "terraform-state-123456789012-us-west-2"   # substituir pelo seu ACCOUNT_ID
key            = "dev/vpc/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "terraform-state-lock"
encrypt        = true
```

### `terraform/environments/staging/backend.tfvars`

```hcl
bucket         = "terraform-state-123456789012-us-west-2"   # substituir pelo seu ACCOUNT_ID
key            = "staging/vpc/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "terraform-state-lock"
encrypt        = true
```

### `terraform/environments/prod/backend.tfvars`

```hcl
bucket         = "terraform-state-123456789012-us-west-2"   # substituir pelo seu ACCOUNT_ID
key            = "prod/vpc/terraform.tfstate"
region         = "us-west-2"
dynamodb_table = "terraform-state-lock"
encrypt        = true
```

**Inicializar com backend.tfvars:**

```bash
terraform init -backend-config=backend.tfvars
```

---

## 📄 terraform.tfvars — Ambiente Dev

```hcl
# ============================================================
# AMBIENTE: Dev
# VPC CIDR: 10.1.0.0/16
# AZs: 2
# NAT: 1 (single — ponto de falha, aceitável em dev)
# Flow Logs: REJECT apenas, retenção 7 dias
# ============================================================

# --- Identificação ---
project_name = "cal"
environment  = "dev"
aws_region   = "us-west-2"

# --- VPC ---
vpc_cidr = "10.1.0.0/16"

# --- Zonas de Disponibilidade (2 AZs em dev) ---
azs = [
  "us-west-2a",
  "us-west-2b"
]

# --- Subnets Públicas (1 por AZ) ---
public_subnet_cidrs = [
  "10.1.1.0/24",   # us-west-2a
  "10.1.2.0/24"    # us-west-2b
]

# --- Subnets Privadas (1 por AZ — aplicação) ---
private_subnet_cidrs = [
  "10.1.11.0/24",  # us-west-2a
  "10.1.12.0/24"   # us-west-2b
]

# --- Subnets de Banco de Dados (1 por AZ — sem rota para internet) ---
database_subnet_cidrs = [
  "10.1.21.0/24",  # us-west-2a
  "10.1.22.0/24"   # us-west-2b
]

# --- NAT Gateway: true = 1 NAT compartilhado (dev/staging) ---
single_nat_gateway = true

# --- VPC Endpoints (gratuitos — sempre ativar) ---
enable_vpc_endpoints = true

# --- VPC Flow Logs ---
flow_log_traffic_type    = "REJECT"  # captura apenas tráfego bloqueado
flow_log_retention_days  = 7         # 7 dias suficientes para dev

# --- Acesso ao Bastion Host (substitua pelo seu IP) ---
# curl ifconfig.me  ← para descobrir seu IP público
bastion_allowed_cidrs = [
  "SEU_IP_AQUI/32"
]
```

---

## 📄 terraform.tfvars — Ambiente Staging

```hcl
# ============================================================
# AMBIENTE: Staging
# VPC CIDR: 10.2.0.0/16
# AZs: 2
# NAT: 1 (single — igual ao dev)
# Flow Logs: REJECT apenas, retenção 7 dias
# ============================================================

# --- Identificação ---
project_name = "cal"
environment  = "staging"
aws_region   = "us-west-2"

# --- VPC ---
vpc_cidr = "10.2.0.0/16"

# --- Zonas de Disponibilidade (2 AZs em staging) ---
azs = [
  "us-west-2a",
  "us-west-2b"
]

# --- Subnets Públicas ---
public_subnet_cidrs = [
  "10.2.1.0/24",   # us-west-2a
  "10.2.2.0/24"    # us-west-2b
]

# --- Subnets Privadas ---
private_subnet_cidrs = [
  "10.2.11.0/24",  # us-west-2a
  "10.2.12.0/24"   # us-west-2b
]

# --- Subnets de Banco de Dados ---
database_subnet_cidrs = [
  "10.2.21.0/24",  # us-west-2a
  "10.2.22.0/24"   # us-west-2b
]

# --- NAT Gateway ---
single_nat_gateway = true

# --- VPC Endpoints ---
enable_vpc_endpoints = true

# --- VPC Flow Logs ---
flow_log_traffic_type    = "REJECT"
flow_log_retention_days  = 7

# --- Bastion: staging pode ter CIDR corporativo mais amplo ---
bastion_allowed_cidrs = [
  "SEU_IP_AQUI/32",
  "IP_DA_VPN_CORPORATIVA/32"
]
```

---

## 📄 terraform.tfvars — Ambiente Prod

```hcl
# ============================================================
# AMBIENTE: Prod
# VPC CIDR: 10.0.0.0/16
# AZs: 3 (alta disponibilidade)
# NAT: 3 (um por AZ — sem ponto único de falha)
# Flow Logs: ALL, retenção 90 dias (conformidade)
# ============================================================

# --- Identificação ---
project_name = "cal"
environment  = "prod"
aws_region   = "us-west-2"

# --- VPC ---
vpc_cidr = "10.0.0.0/16"

# --- Zonas de Disponibilidade (3 AZs em prod para HA) ---
azs = [
  "us-west-2a",
  "us-west-2b",
  "us-west-2c"
]

# --- Subnets Públicas ---
public_subnet_cidrs = [
  "10.0.1.0/24",   # us-west-2a
  "10.0.2.0/24",   # us-west-2b
  "10.0.3.0/24"    # us-west-2c
]

# --- Subnets Privadas ---
private_subnet_cidrs = [
  "10.0.11.0/24",  # us-west-2a
  "10.0.12.0/24",  # us-west-2b
  "10.0.13.0/24"   # us-west-2c
]

# --- Subnets de Banco de Dados ---
database_subnet_cidrs = [
  "10.0.21.0/24",  # us-west-2a
  "10.0.22.0/24",  # us-west-2b
  "10.0.23.0/24"   # us-west-2c
]

# --- NAT Gateway: false = 1 NAT por AZ (obrigatório em prod) ---
single_nat_gateway = false

# --- VPC Endpoints ---
enable_vpc_endpoints = true

# --- VPC Flow Logs: ALL em prod para conformidade (PCI-DSS, SOC 2) ---
flow_log_traffic_type    = "ALL"    # captura tráfego aceito E rejeitado
flow_log_retention_days  = 90       # 90 dias para auditoria

# --- Bastion: restrito — apenas IPs corporativos homologados ---
# ATENÇÃO: nunca usar 0.0.0.0/0 em produção
bastion_allowed_cidrs = [
  "IP_VPN_CORPORATIVA/32",
  "IP_ADMINISTRADOR_1/32"
]
```

---

## 📊 Referência de variáveis

| Variável | Obrigatório | Tipo | Dev | Staging | Prod |
|---|---|---|---|---|---|
| `project_name` | Sim | `string` | `cal` | `cal` | `cal` |
| `environment` | Sim | `string` | `dev` | `staging` | `prod` |
| `aws_region` | Sim | `string` | `us-west-2` | `us-west-2` | `us-west-2` |
| `vpc_cidr` | Sim | `string` | `10.1.0.0/16` | `10.2.0.0/16` | `10.0.0.0/16` |
| `azs` | Sim | `list(string)` | 2 AZs | 2 AZs | 3 AZs |
| `public_subnet_cidrs` | Sim | `list(string)` | 2 CIDRs | 2 CIDRs | 3 CIDRs |
| `private_subnet_cidrs` | Sim | `list(string)` | 2 CIDRs | 2 CIDRs | 3 CIDRs |
| `database_subnet_cidrs` | Sim | `list(string)` | 2 CIDRs | 2 CIDRs | 3 CIDRs |
| `single_nat_gateway` | Sim | `bool` | `true` | `true` | `false` |
| `enable_vpc_endpoints` | Não | `bool` | `true` | `true` | `true` |
| `flow_log_traffic_type` | Não | `string` | `REJECT` | `REJECT` | `ALL` |
| `flow_log_retention_days` | Não | `number` | `7` | `7` | `90` |
| `bastion_allowed_cidrs` | Sim | `list(string)` | Seu IP `/32` | IPs autorizados | IPs corporativos |

---

## ⚙️ Variáveis de ambiente para CI/CD (GitHub Actions)

Configure os seguintes **Secrets** no repositório GitHub (`Settings → Secrets → Actions`):

| Secret | Valor | Propósito |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIAIOSFODNN7EXAMPLE` | Autenticação AWS no pipeline |
| `AWS_SECRET_ACCESS_KEY` | `wJalrXUtnFEMI/...` | Autenticação AWS no pipeline |
| `AWS_REGION` | `us-west-2` | Região padrão do pipeline |
| `TF_STATE_BUCKET` | `terraform-state-123456789012-us-west-2` | Bucket do remote state |

**Uso no workflow:**

```yaml
# .github/workflows/terraform.yml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  AWS_DEFAULT_REGION: ${{ secrets.AWS_REGION }}
```

---

## 🔒 Checklist de segurança antes de commitar

- [ ] Nenhum `AWS_ACCESS_KEY_ID` ou `AWS_SECRET_ACCESS_KEY` em texto claro nos arquivos
- [ ] `bastion_allowed_cidrs` não contém `0.0.0.0/0`
- [ ] `.gitignore` inclui `*.tfvars`, `*.tfstate`, `.terraform/` e `backend.tfvars`
- [ ] `terraform.tfvars` adicionado ao `.gitignore` (valores reais ficam fora do repositório)

### `.gitignore` recomendado para este projeto

```gitignore
# Terraform — nunca commitar
.terraform/
*.tfstate
*.tfstate.backup
*.tfplan
tfplan

# Variáveis com valores reais — nunca commitar
terraform.tfvars
backend.tfvars
*.auto.tfvars

# Credenciais
.aws/
*.pem
*.key
```

---

*Para dúvidas sobre configuração, consulte a [Documentação de Arquitetura](../arquitetura/documentacao-arquitetura.md) ou o [Runbook Operacional](../runbooks/runbook-vpc-operations.md).*
