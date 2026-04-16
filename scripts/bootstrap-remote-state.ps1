# ==============================================================
# bootstrap-remote-state.ps1
# Versão Windows do script de bootstrap.
# Cria o bucket S3 e tabela DynamoDB para o remote state.
# Executar UMA VEZ antes do primeiro terraform init com backend S3.
#
# Uso: powershell -ExecutionPolicy Bypass -File scripts\bootstrap-remote-state.ps1
# ==============================================================

$ErrorActionPreference = "Stop"

$REGION = "us-west-2"

Write-Host ""
Write-Host "=== Bootstrap do Remote State (Terraform) ===" -ForegroundColor Cyan
Write-Host ""

# Verificar AWS CLI
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: AWS CLI nao encontrado." -ForegroundColor Red
    Write-Host "Instale em: https://aws.amazon.com/cli/"
    exit 1
}

# Verificar credenciais
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    $ACCOUNT_ID = $identity.Account
    Write-Host "Conta AWS    : $ACCOUNT_ID" -ForegroundColor Green
    Write-Host "Regiao       : $REGION"
} catch {
    Write-Host "ERRO: Credenciais AWS nao configuradas. Execute: aws configure" -ForegroundColor Red
    exit 1
}

$BUCKET = "terraform-state-$ACCOUNT_ID-$REGION"

Write-Host "Bucket S3    : $BUCKET"
Write-Host ""

$confirm = Read-Host "Confirmar criacao dos recursos? [s/N]"
if ($confirm -notmatch "^[sS]$") {
    Write-Host "Operacao cancelada."
    exit 0
}

# ---- Criar bucket S3 ----
Write-Host ""
Write-Host "=== Criando bucket S3 ===" -ForegroundColor Yellow

$bucketExists = aws s3 ls "s3://$BUCKET" 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "Bucket ja existe: $BUCKET" -ForegroundColor Gray
} else {
    aws s3api create-bucket `
        --bucket $BUCKET `
        --region $REGION `
        --create-bucket-configuration LocationConstraint=$REGION
    Write-Host "Bucket criado: $BUCKET" -ForegroundColor Green
}

# ---- Versionamento ----
Write-Host "Habilitando versionamento..."
aws s3api put-bucket-versioning `
    --bucket $BUCKET `
    --versioning-configuration Status=Enabled
Write-Host "Versionamento habilitado." -ForegroundColor Green

# ---- Criptografia ----
Write-Host "Habilitando criptografia AES-256..."
aws s3api put-bucket-encryption `
    --bucket $BUCKET `
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
Write-Host "Criptografia habilitada." -ForegroundColor Green

# ---- Bloquear acesso publico ----
Write-Host "Bloqueando acesso publico..."
aws s3api put-public-access-block `
    --bucket $BUCKET `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
Write-Host "Acesso publico bloqueado." -ForegroundColor Green

# ---- Atualizar main.tf automaticamente ----
Write-Host ""
Write-Host "=== Atualizando main.tf dos ambientes ===" -ForegroundColor Yellow

$ambientes = @("dev", "staging", "prod")
foreach ($amb in $ambientes) {
    $mainTf = "terraform\environments\$amb\main.tf"
    if (Test-Path $mainTf) {
        (Get-Content $mainTf) -replace "terraform-state-SEU-ACCOUNT-ID-us-west-2", $BUCKET |
            Set-Content $mainTf
        Write-Host "  Atualizado: $mainTf" -ForegroundColor Green
    }
}

# ---- Resumo ----
Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " Bootstrap concluido!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Bucket S3 criado: $BUCKET" -ForegroundColor Cyan
Write-Host ""
Write-Host " Proximos passos:" -ForegroundColor Yellow
Write-Host " 1. Delete o arquivo backend_override.tf dos ambientes (se existir)"
Write-Host " 2. Execute:"
Write-Host "    cd terraform\environments\dev"
Write-Host "    terraform init"
Write-Host "    terraform plan -out=tfplan"
Write-Host "    terraform apply tfplan"
Write-Host ""
