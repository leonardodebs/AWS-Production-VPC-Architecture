# Documentação de Arquitetura — AWS Production VPC Architecture

**Versão:** 1.0.0  
**Data:** 2026-04-15  
**Status:** Ativo  
**Responsável:** Time de Infraestrutura  

---

## 1. Visão geral

Este documento descreve a arquitetura técnica da VPC de produção provisionada na AWS como fundação de toda a plataforma cloud. O projeto implementa uma rede multi-camada, multi-AZ, gerenciada inteiramente por Infraestrutura como Código (IaC) via Terraform, seguindo as diretrizes do **AWS Well-Architected Framework**.

### 1.1 Propósito

A VPC serve como base de rede isolada e segura para todas as cargas de trabalho da plataforma:

- **Isolamento:** separação lógica entre cargas públicas, privadas e de banco de dados
- **Alta disponibilidade:** distribuição de recursos em múltiplas Zonas de Disponibilidade (AZs)
- **Segurança em profundidade:** múltiplas camadas de controle de acesso (NACLs + Security Groups)
- **Observabilidade:** VPC Flow Logs para auditoria e análise de tráfego
- **Eficiência de custo:** VPC Endpoints eliminam o tráfego de S3/DynamoDB pelos NAT Gateways

---

## 2. Escopo e fronteiras

### 2.1 O que este projeto provisiona

| Recurso | Dev | Staging | Prod |
|---|---|---|---|
| VPC | `10.1.0.0/16` | `10.2.0.0/16` | `10.0.0.0/16` |
| Zonas de Disponibilidade | 2 | 2 | 3 |
| Subnets públicas | 2 | 2 | 3 |
| Subnets privadas | 2 | 2 | 3 |
| Subnets de banco de dados | 2 | 2 | 3 |
| NAT Gateways | 1 (compartilhado) | 1 (compartilhado) | 3 (por AZ) |
| VPC Endpoints (S3, DynamoDB) | Sim | Sim | Sim |
| VPC Flow Logs | REJECT — 7 dias | REJECT — 7 dias | ALL — 90 dias |
| Network ACLs | Sim | Sim | Sim |
| Internet Gateway | Sim | Sim | Sim |
| DB Subnet Group | Sim | Sim | Sim |

### 2.2 O que este projeto NÃO provisiona

- Instâncias EC2, ECS, EKS ou RDS (provisionados nos projetos 03 e 07)
- Application Load Balancer (provisionado no projeto 03)
- Certificate Manager / ACM (provisionado no projeto 03)
- IAM Roles de aplicação (provisionados por projeto)

---

## 3. Diagrama de arquitetura

### 3.1 Topologia de rede (Produção — 3 AZs)

```
                        ┌─────────────────────────────────────────────────────┐
                        │              VPC 10.0.0.0/16 (us-west-2)            │
                        │                                                     │
  Internet ──► IGW ──►  │  ┌──── AZ-A ───────┐  ┌──── AZ-B ───────┐  ┌──── AZ-C ───────┐  │
                        │  │ pub: 10.0.1.0/24 │  │ pub: 10.0.2.0/24│  │ pub: 10.0.3.0/24│  │
                        │  │ NAT-GW-A + EIP   │  │ NAT-GW-B + EIP  │  │ NAT-GW-C + EIP  │  │
                        │  │                  │  │                  │  │                  │  │
                        │  │ priv:10.0.11.0/24│  │ priv:10.0.12.0/24│ │ priv:10.0.13.0/24│  │
                        │  │ [EC2/ECS/EKS]    │  │ [EC2/ECS/EKS]   │  │ [EC2/ECS/EKS]   │  │
                        │  │                  │  │                  │  │                  │  │
                        │  │  db:10.0.21.0/24 │  │  db:10.0.22.0/24│  │  db:10.0.23.0/24│  │
                        │  │ [RDS Multi-AZ]   │  │ [RDS Multi-AZ]   │  │ [RDS standby]   │  │
                        │  └──────────────────┘  └──────────────────┘  └──────────────────┘  │
                        │                                                     │
                        │  VPC Endpoint S3 (Gateway)   ─────────────► S3     │
                        │  VPC Endpoint DynamoDB (Gateway) ──────────► DDB   │
                        └─────────────────────────────────────────────────────┘
```

### 3.2 Fluxo de tráfego

```
Usuário (HTTPS :443)
     │
     ▼
Internet Gateway
     │
     ▼
ALB — subnet pública (SG: 80/443 de 0.0.0.0/0)
     │
     ▼  [via NACL público]
App — subnet privada (SG: porta app apenas do SG-ALB)
     │                    │
     ▼                    ▼
RDS — subnet banco    S3 via VPC Endpoint
(SG: 5432 apenas      (sem passar pelo NAT)
 do SG-App)
```

---

## 4. Camadas da arquitetura

### 4.1 Camada 1 — Subnets públicas

**CIDRs:**

| AZ | Dev | Staging | Prod |
|---|---|---|---|
| A | `10.1.1.0/24` | `10.2.1.0/24` | `10.0.1.0/24` |
| B | `10.1.2.0/24` | `10.2.2.0/24` | `10.0.2.0/24` |
| C | — | — | `10.0.3.0/24` |

**Recursos implantados:** Internet Gateway, NAT Gateways, Elastic IPs, Application Load Balancer (projeto 03)

**Route Table:** `0.0.0.0/0 → IGW`; `S3/DDB → VPC Endpoint`

**NACL:** permite entrada em 80, 443 e portas efêmeras (1024–65535); nega todo o resto

---

### 4.2 Camada 2 — Subnets privadas

**CIDRs:**

| AZ | Dev | Staging | Prod |
|---|---|---|---|
| A | `10.1.11.0/24` | `10.2.11.0/24` | `10.0.11.0/24` |
| B | `10.1.12.0/24` | `10.2.12.0/24` | `10.0.12.0/24` |
| C | — | — | `10.0.13.0/24` |

**Recursos implantados:** instâncias de aplicação (EC2 / ECS tasks / EKS nodes)

**Route Table:** `0.0.0.0/0 → NAT-GW` (por AZ em prod); `S3/DDB → VPC Endpoint`

**NACL:** permite tráfego interno da VPC e portas efêmeras; bloqueia qualquer entrada direta da internet

---

### 4.3 Camada 3 — Subnets de banco de dados

**CIDRs:**

| AZ | Dev | Staging | Prod |
|---|---|---|---|
| A | `10.1.21.0/24` | `10.2.21.0/24` | `10.0.21.0/24` |
| B | `10.1.22.0/24` | `10.2.22.0/24` | `10.0.22.0/24` |
| C | — | — | `10.0.23.0/24` |

**Route Table:** **sem rota de saída** — tráfego interno à VPC apenas

**NACL:** permite apenas entrada na porta 5432 da faixa de subnets privadas

> **Nota:** o DB Subnet Group do RDS exige subnets em pelo menos 2 AZs. As subnets de banco foram criadas separadas das privadas para reforçar isolamento e facilitar o Multi-AZ failover do RDS.

---

## 5. Componentes de segurança

### 5.1 Modelo de segurança em camadas

```
Camada         Recurso              Tipo de controle
─────────────────────────────────────────────────────
Perimetral     NACL público         Stateless, nível subnet
Perimetral     NACL privado         Stateless, nível subnet
Instância      SG ALB               Stateful, nível recurso
Instância      SG App               Stateful, nível recurso
Instância      SG Banco             Stateful, nível recurso
Instância      SG Bastion           Stateful, nível recurso
```

### 5.2 Regras dos Security Groups

#### SG — ALB

| Direção | Porta | Protocolo | Origem | Propósito |
|---|---|---|---|---|
| Entrada | 80 | TCP | `0.0.0.0/0` | HTTP |
| Entrada | 443 | TCP | `0.0.0.0/0` | HTTPS |
| Saída | 8080 | TCP | SG-App | Encaminhamento para app |

#### SG — Aplicação

| Direção | Porta | Protocolo | Origem | Propósito |
|---|---|---|---|---|
| Entrada | 8080 | TCP | SG-ALB | Tráfego apenas do ALB |
| Saída | 5432 | TCP | SG-Banco | Conexão com banco |
| Saída | 443 | TCP | `0.0.0.0/0` | API calls via NAT/Endpoint |

#### SG — Banco de dados

| Direção | Porta | Protocolo | Origem | Propósito |
|---|---|---|---|---|
| Entrada | 5432 | TCP | SG-App | PostgreSQL apenas da app |

#### SG — Bastion Host

| Direção | Porta | Protocolo | Origem | Propósito |
|---|---|---|---|---|
| Entrada | 22 | TCP | IP do operador `/32` | SSH restrito |
| Saída | 22 | TCP | VPC CIDR | SSH interno |
| Saída | 5432 | TCP | SG-Banco | Acesso ao banco para DBA |

---

### 5.3 Network ACLs

#### NACL — Subnets Públicas

| Regra | Direção | Porta(s) | Protocolo | Ação |
|---|---|---|---|---|
| 100 | Entrada | 80, 443 | TCP | ALLOW |
| 110 | Entrada | 1024–65535 | TCP | ALLOW (efêmeras) |
| * | Entrada | todos | todos | DENY |
| 100 | Saída | todos | todos | ALLOW |

#### NACL — Subnets Privadas

| Regra | Direção | Porta(s) | Protocolo | Ação |
|---|---|---|---|---|
| 100 | Entrada | todos | todos | ALLOW (VPC interno) |
| * | Entrada | todos | todos | DENY |
| 100 | Saída | todos | todos | ALLOW |

> **Por que NACLs são stateless:** ao contrário dos Security Groups, NACLs não rastreiam estado de conexão. É obrigatório incluir regras de saída para portas efêmeras (1024–65535) para que as respostas das conexões iniciadas externamente possam retornar.

---

### 5.4 VPC Flow Logs

| Ambiente | Modo de captura | Destino | Retenção |
|---|---|---|---|
| Dev | `REJECT` | CloudWatch Logs | 7 dias |
| Staging | `REJECT` | CloudWatch Logs | 7 dias |
| Prod | `ALL` | CloudWatch Logs | 90 dias |

O modo `ALL` em produção captura tanto tráfego aceito quanto rejeitado, permitindo:
- Análise de padrões de tráfego legítimo
- Detecção de tentativas de acesso não autorizado
- Auditoria de conformidade (PCI-DSS, SOC 2)

---

## 6. VPC Endpoints

### 6.1 Gateway Endpoints (gratuitos)

| Serviço | Tipo | Impacto |
|---|---|---|
| Amazon S3 | Gateway | Tráfego S3 não passa pelo NAT — sem custo de dados |
| Amazon DynamoDB | Gateway | Tráfego DDB não passa pelo NAT — sem custo de dados |

**Como funciona:** uma entrada de rota é automaticamente adicionada às route tables privadas e públicas apontando para o endpoint. A aplicação não precisa de nenhuma alteração — o roteamento é transparente.

**Exemplo de economia:** 50 GB/mês de tráfego S3 via NAT = US$ 2,25/mês. Com endpoints = US$ 0,00.

---

## 7. Estratégia de NAT Gateway

### 7.1 Por que NAT por AZ em produção?

Em produção, cada AZ tem seu próprio NAT Gateway. Se uma AZ falhar:

- **Com 1 NAT:** todas as subnets privadas das AZs restantes perdem saída para internet
- **Com 3 NATs:** cada AZ é independente — falha de uma AZ não afeta as outras

### 7.2 Custo vs. disponibilidade

| Configuração | Custo/mês | Disponibilidade |
|---|---|---|
| 1 NAT (dev/staging) | ~US$ 32 | Ponto único de falha por AZ |
| 3 NATs (prod) | ~US$ 97 | HA completo — tolera falha de 1 AZ |

A diferença de US$ 65/mês é justificada em produção onde downtime tem custo de negócio.

---

## 8. Planejamento de CIDR

### 8.1 Separação por ambiente

| Ambiente | VPC CIDR | Propósito |
|---|---|---|
| Prod | `10.0.0.0/16` | Cargas de trabalho de produção |
| Dev | `10.1.0.0/16` | Desenvolvimento e testes |
| Staging | `10.2.0.0/16` | Homologação |

**Justificativa:** CIDRs distintos permitem:

1. **VPC Peering** futuro entre ambientes sem conflito de endereços
2. **Transit Gateway** para topologia hub-and-spoke (projeto futuro)
3. **Seleção de ambiente** por faixa de IP nas regras de firewall e monitoramento

### 8.2 Capacidade por subnet

Subnets `/24` oferecem **251 endereços utilizáveis** por subnet (AWS reserva 5 endereços por subnet). Isso é suficiente para:

- EKS com 100+ pods por nó (cada pod consome 1 IP)
- ASG com dezenas de instâncias por AZ
- Crescimento futuro sem necessidade de re-CIDRing

---

## 9. Módulos Terraform

### 9.1 Estrutura de módulos

```
terraform/
├── modules/
│   ├── vpc/                    # Módulo principal de rede
│   │   ├── main.tf             # VPC, subnets, IGW, NAT, route tables
│   │   ├── variables.tf        # Inputs do módulo
│   │   └── outputs.tf          # IDs exportados para outros módulos
│   ├── security-groups/        # SGs para ALB, app, banco e bastion
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── flow-logs/              # VPC Flow Logs → CloudWatch
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── environments/
    ├── dev/                    # single NAT, 2 AZs, logs REJECT 7d
    ├── staging/                # single NAT, 2 AZs, logs REJECT 7d
    └── prod/                   # NAT por AZ, 3 AZs, logs ALL 90d
```

### 9.2 Módulo VPC — Inputs principais

| Variável | Tipo | Descrição |
|---|---|---|
| `project_name` | `string` | Prefixo dos recursos (ex: `cal`) |
| `environment` | `string` | Ambiente: `dev`, `staging`, `prod` |
| `vpc_cidr` | `string` | CIDR block da VPC |
| `azs` | `list(string)` | Zonas de disponibilidade |
| `public_subnet_cidrs` | `list(string)` | CIDRs das subnets públicas |
| `private_subnet_cidrs` | `list(string)` | CIDRs das subnets privadas |
| `database_subnet_cidrs` | `list(string)` | CIDRs das subnets de banco |
| `single_nat_gateway` | `bool` | `true` = 1 NAT; `false` = 1 NAT por AZ |
| `enable_vpc_endpoints` | `bool` | Cria endpoints S3 e DynamoDB |
| `flow_log_traffic_type` | `string` | `REJECT`, `ACCEPT` ou `ALL` |
| `flow_log_retention_days` | `number` | Retenção dos logs em CloudWatch |

### 9.3 Módulo VPC — Outputs

| Output | Tipo | Descrição |
|---|---|---|
| `vpc_id` | `string` | ID da VPC |
| `public_subnet_ids` | `list(string)` | IDs das subnets públicas |
| `private_subnet_ids` | `list(string)` | IDs das subnets privadas |
| `database_subnet_ids` | `list(string)` | IDs das subnets de banco |
| `nat_public_ips` | `list(string)` | Elastic IPs dos NAT Gateways |
| `db_subnet_group_name` | `string` | Nome do DB Subnet Group para RDS |

### 9.4 Módulo Security Groups — Outputs

| Output | Tipo | Descrição |
|---|---|---|
| `alb_sg_id` | `string` | ID do SG do ALB |
| `app_sg_id` | `string` | ID do SG da aplicação |
| `database_sg_id` | `string` | ID do SG do banco |
| `bastion_sg_id` | `string` | ID do SG do bastion |

---

## 10. Remote State

### 10.1 Backend S3 + DynamoDB Lock

O estado do Terraform é armazenado remotamente para permitir colaboração e prevenir corrupção por execuções paralelas:

| Componente | Recurso AWS | Propósito |
|---|---|---|
| State file | S3 Bucket (versionado) | Armazena o estado atual da infraestrutura |
| Criptografia | SSE-AES256 | Protege dados sensíveis no estado |
| Lock | DynamoDB Table | Previne `apply` simultâneo |

### 10.2 Configuração do backend por ambiente

```hcl
# terraform/environments/prod/main.tf
terraform {
  backend "s3" {
    bucket         = "terraform-state-{ACCOUNT_ID}-us-west-2"
    key            = "prod/vpc/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

---

## 11. Tagging strategy

Todos os recursos recebem as seguintes tags obrigatórias via `default_tags` no provider Terraform:

| Tag | Valor exemplo | Propósito |
|---|---|---|
| `gerenciado-por` | `terraform` | Rastreabilidade — recurso não foi criado manualmente |
| `projeto` | `cal` | Filtro no Cost Explorer por projeto |
| `ambiente` | `prod` | Filtro por ambiente |

> **Por que usar `default_tags` no provider?** Recursos criados por módulos que esquecem de declarar tags individualmente ainda recebem as tags obrigatórias. Garante cobertura 100%.

---

## 12. Consumo por outros projetos

Esta VPC é a fundação para todos os projetos seguintes:

| Projeto | Recursos consumidos |
|---|---|
| **Projeto 02** — Multi-Environment Infra | Workspaces Terraform reutilizando este módulo |
| **Projeto 03** — Auto-Scaling Platform | `vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `alb_sg_id`, `app_sg_id`, `db_subnet_group_name` |
| **Projeto 05** — Infrastructure CI/CD | Pipeline aplica `terraform plan/apply` nesta VPC |
| **Projeto 07** — EKS Cluster | `private_subnet_ids` (com tags `kubernetes.io/role/internal-elb`) |

---

## 13. Referências

- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [AWS Well-Architected — Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [Terraform AWS Provider — VPC](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)
- [VPC Endpoints — Gateway type](https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html)
- [AWS NAT Gateway pricing](https://aws.amazon.com/vpc/pricing/)
- [Network ACLs vs Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-network-acls.html)
