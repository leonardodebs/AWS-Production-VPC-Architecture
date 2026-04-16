# Análise de Custo Real — AWS Production VPC Architecture

> **Região:** us-west-2 (Oregon) | **Preços**: Abril 2026  
> **Importante:** este projeto provisiona APENAS a camada de rede (VPC).  
> Não inclui EC2, RDS, ALB, EKS — esses são provisionados nos projetos 03 e 07.

---

## O que este projeto cria (e o que cobra)

### Recursos GRATUITOS (sem custo)

| Recurso | Qtd Dev | Qtd Prod | Custo |
|---|---|---|---|
| VPC | 1 | 1 | $0,00 |
| Subnets (pública/privada/banco) | 6 | 9 | $0,00 |
| Internet Gateway | 1 | 1 | $0,00 |
| Route Tables | 4 | 6 | $0,00 |
| Network ACLs | 3 | 3 | $0,00 |
| Security Groups | 4 | 4 | $0,00 |
| VPC Endpoint S3 (Gateway) | 1 | 1 | $0,00 |
| VPC Endpoint DynamoDB (Gateway) | 1 | 1 | $0,00 |
| IAM Role + Policy | 1 | 1 | $0,00 |
| DB Subnet Group | 1 | 1 | $0,00 |

### Recursos que GERAM CUSTO

| Recurso | Dev | Prod |
|---|---|---|
| NAT Gateway | 1 | 3 |
| Elastic IP (público IPv4) | 1 | 3 |
| VPC Flow Logs (CloudWatch ingestão) | REJECT ~1 GB/mês | ALL ~5–20 GB/mês |
| CloudWatch Logs (armazenamento) | 7 dias | 90 dias |
| Backend S3 (state file) | ~0,01 GB | ~0,01 GB |
| DynamoDB Lock Table (se usado) | PAY_PER_REQUEST | PAY_PER_REQUEST |

---

## Tabela de Preços Unitários (us-west-2, Abril 2026)

| Serviço | Preço |
|---|---|
| NAT Gateway — hora | $0,045/hora |
| NAT Gateway — dados processados | $0,045/GB |
| IPv4 público (EIP) | **$0,005/hora** ¹ |
| VPC Flow Logs (ingestão vended logs) | $0,50/GB |
| CloudWatch Logs — armazenamento | $0,03/GB/mês |
| S3 Standard | $0,023/GB/mês |
| DynamoDB PAY_PER_REQUEST | ~$0,00 (uso irrisório) |

> ¹ Desde **fevereiro/2024** a AWS cobra $0,005/hora por qualquer IPv4 público, inclusive EIPs associados a NAT Gateways — mudança importante que muitos cálculos antigos não incluem.

---

## Cenário 1 — Dev como laboratório (uso realista)

> Premissa: ligado **8 horas/dia, 20 dias/mês** = **160 horas/mês**  
> Destruir com `terraform destroy` ao fim de cada sessão.

| Recurso | Cálculo | Custo/mês |
|---|---|---|
| NAT Gateway (horas) | 1 × $0,045 × 160h | **$7,20** |
| NAT Gateway (dados) | ~2 GB × $0,045 | **$0,09** |
| Elastic IP | 1 × $0,005 × 160h | **$0,80** |
| Flow Logs REJECT (ingestão) | ~0,5 GB × $0,50 | **$0,25** |
| CloudWatch Logs (storage 7d) | ~0,5 GB × $0,03 | **$0,02** |
| S3 state file | ~0,001 GB × $0,023 | **$0,00** |
| **Total mensal** | | **~$8,36/mês** |

> **Custo por sessão de 8h:** ~$0,42

---

## Cenário 2 — Dev ligado 24/7 (acidental — evitar)

> RISCO: esquecer de destruir após os testes.

| Recurso | Cálculo | Custo/mês |
|---|---|---|
| NAT Gateway (horas) | 1 × $0,045 × 720h | **$32,40** |
| NAT Gateway (dados) | ~5 GB × $0,045 | **$0,23** |
| Elastic IP | 1 × $0,005 × 720h | **$3,60** |
| Flow Logs REJECT (ingestão) | ~1 GB × $0,50 | **$0,50** |
| CloudWatch Logs (storage 7d) | ~1 GB × $0,03 | **$0,03** |
| **Total mensal** | | **~$36,76/mês** |

---

## Cenário 3 — Produção (24/7, carga real)

> 3 NAT Gateways + 3 EIPs + Flow Logs ALL

| Recurso | Cálculo | Custo/mês |
|---|---|---|
| NAT Gateway (horas) | 3 × $0,045 × 720h | **$97,20** |
| NAT Gateway (dados) — leve | ~20 GB × $0,045 | **$0,90** |
| Elastic IPs (3 IPv4 públicos) | 3 × $0,005 × 720h | **$10,80** |
| Flow Logs ALL (ingestão) — leve | ~5 GB × $0,50 | **$2,50** |
| CloudWatch Logs (storage 90d) | ~15 GB × $0,03 | **$0,45** |
| S3 state file | ~0,001 GB × $0,023 | **$0,00** |
| **Total mensal — tráfego leve** | | **~$111,85/mês** |

### Produção com tráfego moderado

| Recurso | Ajuste | Custo/mês |
|---|---|---|
| NAT Gateway (horas) | mesmo | **$97,20** |
| NAT Gateway (dados) | ~100 GB × $0,045 | **$4,50** |
| Elastic IPs | mesmo | **$10,80** |
| Flow Logs ALL | ~20 GB × $0,50 | **$10,00** |
| CloudWatch Logs (storage 90d) | ~50 GB × $0,03 | **$1,50** |
| **Total mensal — tráfego moderado** | | **~$124,00/mês** |

---

## Comparativo dos Cenários

| Cenário | Custo/mês | Custo/ano |
|---|---|---|
| Dev — lab (8h/dia, 20 dias) | ~**$8** | ~**$96** |
| Dev — ligado 24/7 (acidente) | ~**$37** | ~**$444** |
| Staging — 24/7 | ~**$37** | ~**$444** |
| **Prod — tráfego leve** | ~**$112** | ~**$1.344** |
| **Prod — tráfego moderado** | ~**$124** | ~**$1.488** |

> ⚠️ Lembrando: estes valores são **APENAS a camada de VPC**.  
> Uma aplicação real em prod adiciona: EC2/ECS (~$50–200), RDS (~$50–200), ALB (~$20–30).

---

## O que o EIP (IPv4 público) agora custa — mudança de 2024

Antes de fev/2024, EIPs associados a NAT Gateways eram **gratuitos**.  
Desde fev/2024, **todo IPv4 público custa $0,005/hora** = **$3,60/mês por IP**.

| Ambiente | EIPs | Custo EIP/mês |
|---|---|---|
| Dev | 1 | $3,60 |
| Staging | 1 | $3,60 |
| Prod | 3 | **$10,80** |

Para um portfólio com dev + staging + prod rodando juntos: **$18,00/mês só em EIPs**.

---

## Quanto custa parado (sem tráfego)?

O NAT Gateway cobra pela **disponibilidade (hora)**, independente de tráfego.  
Mesmo sem uma única conexão, o custo fixo é:

| Ambiente | Custo fixo/mês (sem dados) |
|---|---|
| Dev (1 NAT + 1 EIP) | $32,40 + $3,60 = **$36,00** |
| Prod (3 NATs + 3 EIPs) | $97,20 + $10,80 = **$108,00** |

> Conclusão: **o principal custo deste projeto é o NAT Gateway** — mesmo sem tráfego.

---

## Economia dos VPC Endpoints (impacto real)

Os endpoints Gateway de S3 e DynamoDB são **gratuitos** e eliminam o custo de dados que passariam pelo NAT:

| Operação | Sem Endpoint | Com Endpoint |
|---|---|---|
| 50 GB de upload S3/mês | $2,25 via NAT | **$0,00** |
| 100 GB de leitura DynamoDB/mês | $4,50 via NAT | **$0,00** |
| 500 GB/mês (workload intenso) | $22,50/mês | **$0,00** |

Para aplicações que usam muito S3 (ex: geração de relatórios, logs, backups), os endpoints pagam a diferença de custo de vários meses em semanas.

---

## Dicas para minimizar custo em laboratório

### 1. Destruir sempre após uso
```powershell
cd terraform\environments\dev
terraform destroy
```
**Economia: $28/mês** (de $36 → $8 com uso de 8h/dia)

### 2. Alertas de billing no AWS Budgets
```bash
# Criar alerta por e-mail quando gastar > $10/mês
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget '{
    "BudgetName": "vpc-lab-alert",
    "BudgetType": "COST",
    "TimeUnit": "MONTHLY",
    "BudgetLimit": {"Amount": "10", "Unit": "USD"}
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "seu@email.com"}]
  }]'
```

### 3. Verificar gastos por tag do projeto
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"projeto","Values":["cal"]}}' \
  --metrics BlendedCost \
  --query 'ResultsByTime[].Total.BlendedCost'
```

### 4. Evitar staging permanente
Staging deve ser criado apenas para homologação pontual — destruir entre ciclos de teste.

---

## Resumo executivo

| | Dev (lab) | Staging | Prod |
|---|---|---|---|
| **Custo mínimo mensal** | $5–10 | $10–20 | $108 |
| **Custo realista mensal** | $8 | $20–30 | $112–124 |
| **Custo máximo (24/7)** | $37 | $37 | $130+ |
| **Principal fator de custo** | NAT Gateway | NAT Gateway | NAT Gateways (×3) |
| **Segundo fator** | EIP | EIP | EIPs (×3) |
| **Risco de custo** | Esquecer de destruir | Deixar 24/7 | Tráfego de dados |

> Fontes: [AWS VPC Pricing](https://aws.amazon.com/vpc/pricing/) · [AWS CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/) · [AWS IPv4 Pricing](https://aws.amazon.com/vpc/ipam/) — verificados em Abril/2026.
