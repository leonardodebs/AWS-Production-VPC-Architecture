#!/usr/bin/env bash
# ==============================================================
# bootstrap-remote-state.sh
# Cria o bucket S3 e a tabela DynamoDB para armazenar o state
# do Terraform remotamente.
#
# Uso: bash scripts/bootstrap-remote-state.sh
# Executar UMA VEZ por conta AWS antes do primeiro terraform init.
# ==============================================================

set -euo pipefail

REGION="us-west-2"
DYNAMO_TABLE="terraform-state-lock"

# ---- Verificações de pré-requisitos ----
echo "=== Verificando pré-requisitos ==="

if ! command -v aws &> /dev/null; then
  echo "ERRO: AWS CLI não encontrado. Instale em: https://aws.amazon.com/cli/"
  exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
  echo "ERRO: Credenciais AWS não configuradas. Execute: aws configure"
  exit 1
fi

# ---- Obter Account ID ----
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="terraform-state-${ACCOUNT_ID}-${REGION}"

echo ""
echo "Account ID : $ACCOUNT_ID"
echo "Região     : $REGION"
echo "Bucket S3  : $BUCKET"
echo "DynamoDB   : $DYNAMO_TABLE"
echo ""

read -p "Confirmar criação dos recursos acima? [s/N]: " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "Operação cancelada."
  exit 0
fi

# ---- Criar bucket S3 ----
echo ""
echo "=== Criando bucket S3 ==="

if aws s3 ls "s3://$BUCKET" &> /dev/null; then
  echo "Bucket já existe: $BUCKET"
else
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
  echo "Bucket criado: $BUCKET"
fi

# ---- Habilitar versionamento ----
echo "=== Habilitando versionamento ==="
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
echo "Versionamento habilitado."

# ---- Habilitar criptografia AES-256 ----
echo "=== Habilitando criptografia AES-256 ==="
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
echo "Criptografia habilitada."

# ---- Bloquear acesso público ----
echo "=== Bloqueando acesso público ao bucket ==="
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "Acesso público bloqueado."

# ---- Criar tabela DynamoDB para lock ----
echo ""
echo "=== Criando tabela DynamoDB para state lock ==="

if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" &> /dev/null; then
  echo "Tabela já existe: $DYNAMO_TABLE"
else
  aws dynamodb create-table \
    --table-name "$DYNAMO_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"

  echo "Aguardando tabela ficar ACTIVE..."
  aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region "$REGION"
  echo "Tabela criada: $DYNAMO_TABLE"
fi

# ---- Resumo final ----
echo ""
echo "=============================================="
echo "Bootstrap concluído com sucesso!"
echo ""
echo "Próximo passo: atualizar o campo 'bucket' nos"
echo "main.tf de cada ambiente:"
echo ""
echo "  bucket = \"$BUCKET\""
echo ""
echo "Em seguida execute em cada ambiente:"
echo "  cd terraform/environments/dev"
echo "  cp terraform.tfvars.example terraform.tfvars"
echo "  # edite o IP do bastion"
echo "  terraform init"
echo "  terraform plan -out=tfplan"
echo "  terraform apply tfplan"
echo "=============================================="
