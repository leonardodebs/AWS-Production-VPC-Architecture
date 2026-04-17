# Runbook: AWS Production VPC Architecture

**Última atualização:** 2026-04-15  
**Responsável:** Time de Infraestrutura  
**Repositório:** `cloud-architecture-lab/01-aws-production-vpc`  

---

## Índice

1. [Bootstrap do Remote State](#1-bootstrap-do-remote-state)
2. [Deploy do Ambiente Dev](#2-deploy-do-ambiente-dev)
3. [Deploy do Ambiente Staging](#3-deploy-do-ambiente-staging)
4. [Deploy do Ambiente Prod](#4-deploy-do-ambiente-prod)
5. [Destruir a Infraestrutura](#5-destruir-a-infraestrutura)
6. [Rotação de Credenciais AWS](#6-rotação-de-credenciais-aws)
7. [Escalar NAT Gateway Manualmente](#7-escalar-nat-gateway-manualmente)
8. [Troubleshooting: sem conectividade nas subnets privadas](#8-troubleshooting-sem-conectividade-nas-subnets-privadas)
9. [Troubleshooting: state lock travado](#9-troubleshooting-state-lock-travado)
10. [Troubleshooting: erro de CIDR conflitante](#10-troubleshooting-erro-de-cidr-conflitante)
11. [Monitorar custos do projeto](#11-monitorar-custos-do-projeto)
12. [Verificar logs de tráfego rejeitado](#12-verificar-logs-de-tráfego-rejeitado)

---

## 1. Bootstrap do Remote State

**Quando usar:** antes do primeiro `terraform init` em qualquer ambiente. Executar apenas uma vez por conta AWS.

**Tempo estimado:** 5 minutos  
**Impacto:** Nenhum (apenas cria recursos de controle)

### Pré-requisitos

- [ ] AWS CLI instalado e configurado (`aws configure`)
- [ ] Permissões de administrador na conta AWS
- [ ] Região de destino definida: `us-west-2`

### Passo 1 — Obter o Account ID e criar o bucket S3

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="terraform-state-${ACCOUNT_ID}-us-west-2"

echo "Account ID: $ACCOUNT_ID"
echo "Bucket que será criado: $BUCKET"
```

**Saída esperada:**
```
Account ID: 123456789012
Bucket que será criado: terraform-state-123456789012-us-west-2
```

### Passo 2 — Criar o bucket S3

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
```

**Saída esperada:**
```json
{
    "Location": "http://terraform-state-123456789012-us-west-2.s3.amazonaws.com/"
}
```

### Passo 3 — Habilitar versionamento no bucket

```bash
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
```

**O que verificar:** nenhuma saída = sucesso. Confirme com:

```bash
aws s3api get-bucket-versioning --bucket "$BUCKET"
```

**Saída esperada:**
```json
{ "Status": "Enabled" }
```

### Passo 4 — Habilitar criptografia AES-256

```bash
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### Passo 5 — Criar tabela DynamoDB para lock

```bash
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

**Saída esperada:**
```json
{
    "TableDescription": {
        "TableName": "terraform-state-lock",
        "TableStatus": "CREATING",
        ...
    }
}
```

Aguarde o status mudar para `ACTIVE`:

```bash
aws dynamodb wait table-exists --table-name terraform-state-lock --region us-west-2
echo "Tabela pronta!"
```

### Passo 6 — Atualizar os backends nos main.tf

Abra cada `terraform/environments/*/main.tf` e substitua o placeholder pelo nome real do bucket:

```hcl
backend "s3" {
  bucket = "terraform-state-123456789012-us-west-2"   # ← seu bucket aqui
  ...
}
```

### Verificação pós-execução

```bash
# Listar bucket criado
aws s3 ls | grep terraform-state

# Confirmar tabela DynamoDB
aws dynamodb list-tables --region us-west-2 | grep terraform-state-lock
```

---

## 2. Deploy do Ambiente Dev

**Quando usar:** primeiros testes da infraestrutura, validação de módulos.

**Tempo estimado:** ~3 minutos (inicializar) + ~3 minutos de apply  
**Impacto:** Cria ~25 recursos AWS — incorre custo enquanto ligado (~US$ 37/mês se ficar 24h)

> ⚠️ **Destruir após uso** para evitar cobranças desnecessárias.

### Pré-requisitos

- [ ] Bootstrap do remote state concluído (seção 1)
- [ ] Bucket S3 e tabela DynamoDB existem
- [ ] Credenciais AWS configuradas: `aws sts get-caller-identity`
- [ ] Terraform >= 1.5 instalado: `terraform --version`

### Passo 1 — Navegar para o diretório de dev

```bash
cd terraform/environments/dev
```

### Passo 2 — Inicializar o Terraform

```bash
terraform init
```

**Saída esperada (trecho):**
```
Terraform has been successfully initialized!
Backend configuration changed! The configuration is stored in .terraform/terraform.tfstate.
```

### Passo 3 — Validar a configuração (sem chamar a AWS)

```bash
terraform validate
```

**Saída esperada:**
```
Success! The configuration is valid.
```

### Passo 4 — Formatar o código (boa prática)

```bash
terraform fmt -recursive ../../
```

### Passo 5 — Revisar o plano de execução

```bash
terraform plan -out=tfplan
```

**O que verificar:** o plano deve mostrar apenas recursos do tipo:
- `aws_vpc`
- `aws_subnet`
- `aws_internet_gateway`
- `aws_nat_gateway`
- `aws_eip`
- `aws_route_table` e `aws_route_table_association`
- `aws_network_acl`
- `aws_vpc_endpoint`
- `aws_security_group`
- `aws_cloudwatch_log_group`
- `aws_flow_log`

Deve **não** aparecer `aws_instance`, `aws_db_instance` ou `aws_lb` — esses são provisionados em outros projetos.

### Passo 6 — Aplicar

```bash
terraform apply tfplan
```

### Passo 7 — Verificar os outputs

```bash
terraform output
```

**Saída esperada (exemplo):**
```
vpc_id               = "vpc-0abc1234def56789a"
public_subnet_ids    = ["subnet-0a1b2c3d4e", "subnet-0b2c3d4e5f"]
private_subnet_ids   = ["subnet-0c3d4e5f6g", "subnet-0d4e5f6g7h"]
database_subnet_ids  = ["subnet-0e5f6g7h8i", "subnet-0f6g7h8i9j"]
nat_public_ips       = ["54.0.0.1"]
db_subnet_group_name = "cal-dev-db-subnet-group"
alb_sg_id            = "sg-0111222333444555a"
app_sg_id            = "sg-0222333444555666b"
database_sg_id       = "sg-0333444555666777c"
```

---

## 3. Deploy do Ambiente Staging

Idêntico ao dev. Diferenças:

- Diretório: `terraform/environments/staging`
- VPC CIDR: `10.2.0.0/16`
- 1 NAT Gateway (single AZ)

```bash
cd terraform/environments/staging
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

---

## 4. Deploy do Ambiente Prod

**Tempo estimado:** ~3 min (init) + ~5 min (apply — 3 NAT Gateways)  
**Impacto:** Cria ~35 recursos AWS — custo ~US$ 115/mês se ficar ligado  
**Atenção:** NAT Gateways são aprovisionados sequencialmente — aguarde a conclusão.

> ⚠️ **Para laboratório**: destruir após cada sessão de testes ou usar o ambiente dev.  
> Em produção real: jamais destruir sem aprovação do responsável e janela de manutenção.

### Pré-requisitos adicionais para prod

- [ ] Revisão do `terraform plan` aprovada por pelo menos 1 responsável
- [ ] Backup do state file atual verificado no S3
- [ ] Alerta de billing configurado no AWS Budgets

### Passo 1 — Verificar a identidade AWS antes de aplicar em prod

```bash
aws sts get-caller-identity
```

Confirme que a conta (`Account`) e o usuário/role correspondem ao ambiente de produção.

### Passo 2 — Aplicar

```bash
cd terraform/environments/prod
terraform init
terraform plan -out=tfplan

# Revisar o plano com atenção — 3 NATs, 3 EIPs, Flow Logs ALL
terraform apply tfplan
```

### Passo 3 — Confirmar os 3 NAT Gateways

```bash
aws ec2 describe-nat-gateways \
  --filter "Name=tag:ambiente,Values=prod" \
  --query 'NatGateways[].{ID:NatGatewayId,AZ:SubnetId,State:State}' \
  --output table
```

**Saída esperada:**
```
--------------------------------------------------
|          DescribeNatGateways                   |
+---------------------------+--------+-----------+
|          AZ               | ID     |  State    |
+---------------------------+--------+-----------+
|  subnet-...               | nat-.. | available |
|  subnet-...               | nat-.. | available |
|  subnet-...               | nat-.. | available |
+---------------------------+--------+-----------+
```

---

## 5. Destruir a Infraestrutura

**Quando usar:** após sessão de laboratório ou ao encerrar o ambiente.

**Impacto:** Remove TODOS os recursos criados pelo Terraform naquele ambiente.  
**Pré-requisito:** Nenhum outro projeto (03, 07) deve depender desta VPC no momento.

```bash
cd terraform/environments/dev   # ou staging / prod

terraform plan -destroy         # Revisar o que será destruído
terraform destroy               # Digitar "yes" para confirmar
```

**Verificação pós-destruição:**

```bash
# Confirmar que a VPC foi removida
aws ec2 describe-vpcs \
  --filters "Name=tag:projeto,Values=cal" \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,State:State}' \
  --output table
```

Se a tabela estiver vazia, a destruição foi bem-sucedida.

---

## 6. Rotação de Credenciais AWS

**Quando usar:** periodicamente (recomendado a cada 90 dias), ou após suspeita de vazamento.

**Tempo estimado:** 10 minutos  
**Impacto:** Nenhum — o novo par de chaves é criado antes de o antigo ser desativado.

### Passo 1 — Criar novo par de chaves de acesso

```bash
aws iam create-access-key --user-name SEU-USUARIO-IAM
```

Copie `AccessKeyId` e `SecretAccessKey` retornados.

### Passo 2 — Atualizar as credenciais locais

```bash
aws configure
# AWS Access Key ID [****xxxx]: NOVA_ACCESS_KEY
# AWS Secret Access Key [****xxxx]: NOVA_SECRET_KEY
# Default region name [us-west-2]: (enter)
# Default output format [json]: (enter)
```

### Passo 3 — Verificar que o novo par funciona

```bash
aws sts get-caller-identity
```

### Passo 4 — Desativar o par antigo

```bash
aws iam update-access-key \
  --access-key-id ANTIGA_ACCESS_KEY \
  --status Inactive \
  --user-name SEU-USUARIO-IAM
```

### Passo 5 — Aguardar 24h e excluir o par antigo

```bash
aws iam delete-access-key \
  --access-key-id ANTIGA_ACCESS_KEY \
  --user-name SEU-USUARIO-IAM
```

---

## 7. Escalar NAT Gateway Manualmente

**Quando usar:** ambiente dev/staging onde existe apenas 1 NAT Gateway e você precisa de HA temporário (ex.: simulação de drills de resiliência).

> **Nota:** a forma correta de ter NAT HA é alterar `single_nat_gateway = false` no `variables.tf` e executar `terraform apply`. O procedimento abaixo é apenas para emergências temporárias.

### Passo 1 — Identificar as subnets públicas

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:tipo,Values=publica" "Name=tag:ambiente,Values=dev" \
  --query 'Subnets[].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}' \
  --output table
```

### Passo 2 — Alterar variável via Terraform (preferencial)

```hcl
# terraform/environments/dev/variables.tf
variable "single_nat_gateway" {
  default = false   # ← alterar de true para false
}
```

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

---

## 8. Troubleshooting: sem conectividade nas subnets privadas

**Sintoma:** instâncias nas subnets privadas não conseguem fazer chamadas de saída (ex.: `curl https://api.example.com` falha).

### Verificação 1 — Route table das subnets privadas

```bash
# Obter o ID da subnet privada
SUBNET_ID="subnet-xxxxxxxxx"

# Ver a route table associada
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'RouteTables[].Routes' \
  --output json
```

**O que procurar:** deve existir uma rota `0.0.0.0/0` apontando para um `NatGatewayId`.

Se não existir, o NAT Gateway não está associado. Execute `terraform apply` para recriar as rotas.

### Verificação 2 — Status do NAT Gateway

```bash
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].{ID:NatGatewayId,State:State,Subnet:SubnetId}' \
  --output table
```

Se o NAT Gateway estiver com estado diferente de `available`, pode estar corrompido. Destrua e recrie via Terraform.

### Verificação 3 — NACLs bloqueando tráfego

```bash
# Ver as regras da NACL associada à subnet privada
aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query 'NetworkAcls[].Entries' \
  --output json
```

**O que verificar:** deve haver regra de saída (`"Egress": true`) que permite `0.0.0.0/0` ou pelo menos portas 80/443 e 1024-65535.

### Ação corretiva

```bash
cd terraform/environments/dev
terraform plan    # verifica drift
terraform apply   # corrige o estado
```

---

## 9. Troubleshooting: state lock travado

**Sintoma:** `terraform plan` ou `terraform apply` retorna:

```
Error: Error acquiring the state lock
...
Lock Info:
  ID:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  Path:   dev/vpc/terraform.tfstate
  ...
```

**Causa comum:** `terraform apply` foi interrompido abruptamente (Ctrl+C, falha de rede). O lock ficou na tabela DynamoDB.

### Verificação — Confirmar que não há apply em execução

Antes de remover o lock, verifique se outro membro do time não está executando um apply legítimo.

```bash
# Ver o item de lock na tabela DynamoDB
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "terraform-state-ACCOUNT_ID-us-west-2/dev/vpc/terraform.tfstate"}}' \
  --region us-west-2
```

Se `Created` for recente e você souber que foi um apply interrompido, prossiga.

### Ação corretiva — Forçar unlock

```bash
# o ID do lock está na mensagem de erro acima
terraform force-unlock LOCK_ID_AQUI
```

Confirme com `yes` quando solicitado.

---

## 10. Troubleshooting: erro de CIDR conflitante

**Sintoma:** `terraform apply` falha com:

```
Error: error creating VPC: InvalidVpc.Conflict:
The CIDR '10.0.0.0/16' conflicts with another VPC in your account.
```

**Causa:** outra VPC na conta já usa o mesmo CIDR, ou uma VPC anterior não foi completamente destruída.

### Verificação

```bash
aws ec2 describe-vpcs \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

### Ação corretiva

**Opção 1:** Destruir a VPC conflitante (se não estiver em uso):

```bash
aws ec2 delete-vpc --vpc-id vpc-CONFLITANTE
```

**Opção 2:** Alterar o CIDR no `variables.tf`:

```hcl
variable "vpc_cidr" {
  default = "10.10.0.0/16"   # ← novo CIDR sem conflito
}
```

E atualizar os CIDRs das subnets de forma consistente.

---

## 11. Monitorar custos do projeto

**Quando usar:** verificação semanal ou após suspeita de recursos esquecidos ligados.

### Ver gasto acumulado do mês

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"projeto","Values":["cal"]}}' \
  --metrics BlendedCost \
  --query 'ResultsByTime[].Total.BlendedCost'
```

### Ver gasto por serviço

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"projeto","Values":["cal"]}}' \
  --group-by Type=DIMENSION,Key=SERVICE \
  --metrics BlendedCost \
  --query 'ResultsByTime[].Groups[].{Servico:Keys[0],Custo:Metrics.BlendedCost.Amount}' \
  --output table
```

### Verificar recursos provisionados (NAT Gateways ativos)

```bash
# Listar NAT Gateways com estado "available" (cobrando)
aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[].{ID:NatGatewayId,Subnet:SubnetId,State:State}' \
  --output table
```

Se houver NAT Gateways ativos quando não deveria, execute `terraform destroy`.

---

## 12. Verificar logs de tráfego rejeitado

**Quando usar:** investigar falhas de conectividade, auditar tentativas de acesso não autorizado.

> **Disponível apenas quando Flow Logs estão habilitados.** Em dev/staging, apenas tráfego REJECT é capturado. Em prod, todo o tráfego (ALL) é capturado.

### Passo 1 — Identificar o Log Group

```bash
# O nome segue o padrão: /vpc/cal-{ambiente}-flow-logs
aws logs describe-log-groups \
  --log-group-name-prefix /vpc/cal \
  --query 'logGroups[].logGroupName'
```

### Passo 2 — Consultar logs de rejeição das últimas 2 horas

```bash
aws logs filter-log-events \
  --log-group-name "/vpc/cal-prod-flow-logs" \
  --start-time $(($(date +%s) - 7200))000 \
  --filter-pattern "REJECT" \
  --query 'events[].message' \
  --output text | head -50
```

### Interpretar um registro de Flow Log

```
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
2       123456789  eni-abc123   1.2.3.4 10.0.11.5 54321  5432     6        5       300   ...  ... REJECT OK
```

| Campo | Significado |
|---|---|
| `srcaddr` | IP de origem |
| `dstaddr` | IP de destino |
| `srcport` / `dstport` | Portas de origem e destino |
| `protocol` | 6=TCP, 17=UDP, 1=ICMP |
| `action` | `ACCEPT` ou `REJECT` |

### Filtrar tentativas na porta 5432 (banco) vindas de fora

```bash
aws logs filter-log-events \
  --log-group-name "/vpc/cal-prod-flow-logs" \
  --start-time $(($(date +%s) - 86400))000 \
  --filter-pattern "5432 REJECT" \
  --query 'events[].message'
```

---

## Histórico de execuções

| Data | Ambiente | Operação | Executado por | Resultado | Observações |
|---|---|---|---|---|---|
| 2026-04-15 | dev | `terraform apply` | Leonardo | Sucesso | Primeiro deploy |
| — | — | — | — | — | — |
