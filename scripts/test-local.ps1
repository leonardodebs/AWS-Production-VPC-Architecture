# ==============================================================
# test-local.ps1
# Valida e testa o projeto Terraform localmente no Windows.
#
# Uso (sem credenciais AWS - apenas fmt e validate):
#   powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1 -SomenteValidar
#
# Uso (com credenciais AWS - roda o plan):
#   powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1 -Ambiente staging
# ==============================================================

param(
    [string]$Ambiente = "dev",
    [switch]$SomenteValidar
)

$ErrorActionPreference = "Stop"
$RaizProjeto = Split-Path -Parent $PSScriptRoot
$DirAmbiente = Join-Path $RaizProjeto "terraform\environments\$Ambiente"
$BackendOverride = Join-Path $DirAmbiente "backend_override.tf"
$BackendExample  = Join-Path $DirAmbiente "backend-local.tf.example"
$TfVars          = Join-Path $DirAmbiente "terraform.tfvars"
$TfVarsExample   = Join-Path $DirAmbiente "terraform.tfvars.example"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " AWS VPC Architecture - Teste Local        " -ForegroundColor Cyan
Write-Host " Ambiente : $Ambiente                      " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ==============================================================
# PASSO 1 - Verificar Terraform
# ==============================================================
Write-Host "[1/5] Verificando Terraform..." -ForegroundColor Yellow

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "  Terraform nao encontrado." -ForegroundColor Red

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "  Instalando via winget..." -ForegroundColor Yellow
        winget install --id Hashicorp.Terraform -e --accept-source-agreements --accept-package-agreements
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
    }

    if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  Instale o Terraform manualmente:" -ForegroundColor Red
        Write-Host "  https://developer.hashicorp.com/terraform/downloads"
        exit 1
    }
}

$tfVersion = terraform version -json | ConvertFrom-Json | Select-Object -ExpandProperty terraform_version
Write-Host "  OK - Terraform $tfVersion" -ForegroundColor Green

# ==============================================================
# PASSO 2 - Verificar AWS CLI (pulado em -SomenteValidar)
# ==============================================================
if ($SomenteValidar) {
    Write-Host ""
    Write-Host "[2/5] Modo SomenteValidar - pulando AWS CLI e credenciais." -ForegroundColor Gray
} else {
    Write-Host ""
    Write-Host "[2/5] Verificando AWS CLI e credenciais..." -ForegroundColor Yellow

    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Host "  AWS CLI nao encontrado." -ForegroundColor Red
        Write-Host "  Instale em: https://aws.amazon.com/cli/"
        Write-Host ""
        Write-Host "  Para apenas validar sintaxe (sem AWS), use:"
        Write-Host "  powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1 -SomenteValidar"
        exit 1
    }

    $awsVer = (aws --version 2>&1)
    Write-Host "  OK - $awsVer" -ForegroundColor Green

    Write-Host "  Verificando credenciais..." -ForegroundColor Yellow
    $callerJson = aws sts get-caller-identity --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Credenciais invalidas ou nao configuradas." -ForegroundColor Red
        Write-Host "  Execute: aws configure"
        Write-Host "  Ou use -SomenteValidar para pular."
        exit 1
    }
    $caller = $callerJson | ConvertFrom-Json
    Write-Host "  Conta  : $($caller.Account)" -ForegroundColor Green
    Write-Host "  Usuario: $($caller.Arn)"      -ForegroundColor Green
}

# ==============================================================
# PASSO 3 - Ativar backend LOCAL (sem S3)
# ==============================================================
Write-Host ""
Write-Host "[3/5] Ativando backend local (sem S3)..." -ForegroundColor Yellow

if (Test-Path $BackendExample) {
    Copy-Item $BackendExample $BackendOverride -Force
} else {
    $backendContent = 'terraform {' + "`n" +
                      '  backend "local" {' + "`n" +
                      '    path = "terraform.tfstate.local"' + "`n" +
                      '  }' + "`n" +
                      '}'
    Set-Content -Path $BackendOverride -Value $backendContent
}
Write-Host "  Backend local criado: backend_override.tf" -ForegroundColor Green

# ==============================================================
# PASSO 4 - terraform.tfvars
# ==============================================================
Write-Host ""
Write-Host "[4/5] Verificando terraform.tfvars..." -ForegroundColor Yellow

if (-not (Test-Path $TfVars)) {
    if (-not (Test-Path $TfVarsExample)) {
        Write-Host "  ERRO: terraform.tfvars.example nao encontrado." -ForegroundColor Red
        exit 1
    }
    Copy-Item $TfVarsExample $TfVars
    Write-Host "  Criado terraform.tfvars a partir do exemplo." -ForegroundColor Green

    # Detectar IP publico automaticamente
    try {
        $meuIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 5).Trim()
        Write-Host "  Seu IP publico detectado: $meuIp" -ForegroundColor Cyan
        (Get-Content $TfVars) -replace "SEU_IP_AQUI", $meuIp | Set-Content $TfVars
        Write-Host "  IP $meuIp/32 inserido automaticamente no bastion_allowed_cidrs." -ForegroundColor Green
    } catch {
        Write-Host "  Nao foi possivel detectar seu IP. Edite manualmente:" -ForegroundColor Yellow
        Write-Host "  Arquivo: $TfVars"
        Write-Host "  Campo  : bastion_allowed_cidrs = [SEU_IP/32]"
    }
} else {
    Write-Host "  terraform.tfvars ja existe." -ForegroundColor Green
}

# ==============================================================
# PASSO 5 - Executar Terraform
# ==============================================================
Write-Host ""
Write-Host "[5/5] Executando Terraform..." -ForegroundColor Yellow

Push-Location $DirAmbiente

try {
    # Formatar
    Write-Host ""
    Write-Host "  > terraform fmt -recursive" -ForegroundColor Cyan
    terraform fmt -recursive "$RaizProjeto\terraform"
    Write-Host "  Formatacao OK." -ForegroundColor Green

    # Init com backend local
    Write-Host ""
    Write-Host "  > terraform init -reconfigure" -ForegroundColor Cyan
    terraform init -reconfigure -input=false
    if ($LASTEXITCODE -ne 0) { throw "Erro no terraform init." }
    Write-Host "  Init OK." -ForegroundColor Green

    # Validate
    Write-Host ""
    Write-Host "  > terraform validate" -ForegroundColor Cyan
    terraform validate
    if ($LASTEXITCODE -ne 0) { throw "Erro no terraform validate." }
    Write-Host "  Sintaxe valida." -ForegroundColor Green

    # Plan (apenas com AWS)
    if (-not $SomenteValidar) {
        Write-Host ""
        Write-Host "  > terraform plan" -ForegroundColor Cyan
        terraform plan -out=tfplan.local -input=false
        if ($LASTEXITCODE -ne 0) { throw "Erro no terraform plan." }
        Write-Host ""
        Write-Host "  Plan OK! Arquivo gerado: tfplan.local" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Para aplicar (cria recursos reais na AWS):" -ForegroundColor Yellow
        Write-Host "  terraform apply tfplan.local"
        Write-Host ""
        Write-Host "  Para destruir apos os testes:" -ForegroundColor Yellow
        Write-Host "  terraform destroy"
    }
} catch {
    Write-Host ""
    Write-Host "  ERRO: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location

# ==============================================================
# RESUMO
# ==============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Validacao local concluida com sucesso!    " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

if ($SomenteValidar) {
    Write-Host "Proximos passos:" -ForegroundColor Cyan
    Write-Host "  1. Instale AWS CLI : https://aws.amazon.com/cli/"
    Write-Host "  2. Configure       : aws configure"
    Write-Host "  3. Teste com plan  : powershell -ExecutionPolicy Bypass -File scripts\test-local.ps1"
} else {
    Write-Host "Proximos passos para deploy com S3 backend:" -ForegroundColor Cyan
    Write-Host "  1. Execute bootstrap: powershell -ExecutionPolicy Bypass -File scripts\bootstrap-remote-state.ps1"
    Write-Host "  2. Delete o arquivo: terraform\environments\$Ambiente\backend_override.tf"
    Write-Host "  3. Execute: terraform init && terraform plan -out=tfplan && terraform apply tfplan"
}

Write-Host ""
