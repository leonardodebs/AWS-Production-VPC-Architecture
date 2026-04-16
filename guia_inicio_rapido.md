# Guia de Início Rápido — AWS Production VPC Architecture

> Como rodar o projeto do zero: validação local → deploy dev → deploy prod.

---

## Estrutura criada

```
AWS Production VPC Architecture/
├── .github/
│   └── workflows/
│       └── terraform.yml          ← CI/CD completo
├── .gitignore                     ← protege tfvars, state, credenciais
├── readme.md                      ← documentação principal
├── scripts/
│   ├── bootstrap-remote-state.sh  ← cria bucket S3 + DynamoDB (executar 1x)
│   └── validate-local.sh          ← valida sem credenciais AWS
├── docs/
│   ├── index.md
│   ├── arquitetura/documentacao-arquitetura.md
│   ├── runbooks/runbook-vpc-operations.md
│   └── config/variaveis-de-ambiente.md
└── terraform/
    ├── modules/
    │   ├── vpc/                   ← VPC, subnets, NAT, NACLs, Endpoints
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   ├── security-groups/       ← SGs ALB, App, DB, Bastion
    │   │   ├── main.tf
    │   │   ├── variables.tf
    │   │   └── outputs.tf
    │   └── flow-logs/             ← CloudWatch Flow Logs
    │       ├── main.tf
    │       ├── variables.tf
    │       └── outputs.tf
    └── environments/
        ├── dev/                   ← 2 AZs, 1 NAT, REJECT logs 7d
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars.example
        ├── staging/               ← 2 AZs, 1 NAT, REJECT logs 7d
        │   ├── main.tf
        │   ├── variables.tf
        │   ├── outputs.tf
        │   └── terraform.tfvars.example
        └── prod/                  ← 3 AZs, 3 NATs, ALL logs 90d
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            └── terraform.tfvars.example
```

---

## Fase 1 — Validação local (sem credenciais AWS)

```bash
# Instalar dependências
terraform --version   # >= 1.5
pip install checkov   # análise de segurança estática

# Validar o projeto inteiro
bash scripts/validate-local.sh dev
```

**O que valida:**
- `terraform fmt` — formatação consistente
- `terraform validate` — sintaxe HCL
- `checkov` — boas práticas de segurança
- `tfsec` — vulnerabilidades (opcional)

---

## Fase 2 — Configurar credenciais AWS

```bash
aws configure
# AWS Access Key ID:     SUA_KEY_ID
# AWS Secret Access Key: SUA_SECRET_KEY
# Default region name:   us-west-2
# Default output format: json

# Confirmar identidade
aws sts get-caller-identity
```

---

## Fase 3 — Bootstrap do Remote State (executar UMA vez)

```bash
bash scripts/bootstrap-remote-state.sh
```

O script vai exibir o nome do bucket criado (ex: `terraform-state-123456789012-us-west-2`).

**Atualizar os `main.tf` de cada ambiente** com esse bucket:

```hcl
# terraform/environments/dev/main.tf  (e staging, prod)
backend "s3" {
  bucket = "terraform-state-123456789012-us-west-2"   # ← seu bucket
  ...
}
```

---

## Fase 4 — Deploy Dev

```bash
# Configurar variáveis
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars

# Editar: substituir SEU_IP_AQUI pelo seu IP público
# Descobrir seu IP: curl ifconfig.me
nano terraform.tfvars   # ou code terraform.tfvars

# Deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Verificar outputs
terraform output
```

**Recursos criados (~25 recursos, ~3 minutos):**
- 1 VPC (`10.1.0.0/16`)
- 6 Subnets (2 públicas + 2 privadas + 2 banco)
- 1 Internet Gateway
- 1 NAT Gateway + 1 Elastic IP
- 3 Route Tables + associações
- 3 NACLs
- 2 VPC Endpoints (S3 + DynamoDB)
- 4 Security Groups (ALB, App, DB, Bastion)
- 1 CloudWatch Log Group + 1 Flow Log
- 1 IAM Role + Policy

> ⚠️ **Custo estimado:** ~US$ 37/mês se ficar ligado 24h. **Destruir após uso:**
> ```bash
> terraform destroy
> ```

---

## Fase 5 — Deploy Staging

```bash
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
# Editar seu IP no terraform.tfvars

terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Fase 6 — Deploy Prod

> ⚠️ Prod cria 3 NAT Gateways — custo ~US$ 115/mês. Use apenas em produção real.

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
# Editar IPs autorizados (VPN corporativa)

terraform init
terraform plan -out=tfplan   # revisar com atenção
terraform apply tfplan        # confirmar "yes"
```

---

## CI/CD — GitHub Actions

O workflow `.github/workflows/terraform.yml` automatiza:

| Evento | Job executado |
|---|---|
| Pull Request aberto | Validação + Plan dev (comentado no PR) |
| Push em `main` | Apply automático em dev |
| Push de tag `v*.*.*` | Plan prod (artefato para revisão manual) |

**Secrets necessários no repositório:**

```
Settings → Secrets → Actions → New repository secret

AWS_ACCESS_KEY_ID      = sua chave
AWS_SECRET_ACCESS_KEY  = sua chave secreta
```

---

## Outputs disponíveis após deploy

```bash
terraform output vpc_id               # vpc-xxxxxxxxxxxxxxxxx
terraform output public_subnet_ids    # ["subnet-xxx", "subnet-yyy"]
terraform output private_subnet_ids   # ["subnet-aaa", "subnet-bbb"]
terraform output database_subnet_ids  # ["subnet-ddd", "subnet-eee"]
terraform output nat_public_ips       # ["54.x.x.x"]
terraform output db_subnet_group_name # cal-dev-db-subnet-group
terraform output alb_sg_id            # sg-xxxxxxxx
terraform output app_sg_id            # sg-yyyyyyyy
terraform output database_sg_id       # sg-zzzzzzzz
```

Esses outputs são consumidos pelos Projetos 03 (Auto-Scaling Platform) e 07 (EKS Cluster).
