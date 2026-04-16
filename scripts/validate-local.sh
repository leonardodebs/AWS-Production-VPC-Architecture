#!/usr/bin/env bash
# ==============================================================
# validate-local.sh
# Validações locais sem precisar de credenciais AWS reais.
# Executa: fmt, validate e checkov (análise de segurança estática).
#
# Uso: bash scripts/validate-local.sh [dev|staging|prod]
# Dependências: terraform >= 1.5, checkov (pip install checkov)
# ==============================================================

set -euo pipefail

ENVIRONMENT="${1:-dev}"
TERRAFORM_DIR="terraform/environments/$ENVIRONMENT"

echo "=== Validando ambiente: $ENVIRONMENT ==="
echo ""

# ---- Verificar dependências ----
for cmd in terraform; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERRO: '$cmd' não encontrado. Instale e tente novamente."
    exit 1
  fi
done

# ---- Formatar código ----
echo "=== [1/4] Formatando código (terraform fmt) ==="
terraform fmt -recursive terraform/
echo "Formatação concluída."

# ---- Validar sintaxe (sem backend) ----
echo ""
echo "=== [2/4] Validando sintaxe (terraform validate) ==="
cd "$TERRAFORM_DIR"

# Init sem backend para validação local
terraform init -backend=false -input=false > /dev/null 2>&1
terraform validate
echo "Sintaxe válida."
cd - > /dev/null

# ---- Checkov (análise de segurança estática) ----
echo ""
echo "=== [3/4] Análise de segurança (checkov) ==="

if command -v checkov &> /dev/null; then
  checkov -d "terraform/" \
    --framework terraform \
    --quiet \
    --compact || true
  echo "Checkov concluído (verifique resultados acima)."
else
  echo "AVISO: checkov não instalado. Para instalar: pip install checkov"
  echo "Pulando análise de segurança..."
fi

# ---- tfsec (análise de segurança alternativa) ----
echo ""
echo "=== [4/4] Análise tfsec (opcional) ==="

if command -v tfsec &> /dev/null; then
  tfsec "terraform/" --minimum-severity MEDIUM || true
else
  echo "AVISO: tfsec não instalado. Para instalar: https://github.com/aquasecurity/tfsec"
  echo "Pulando tfsec..."
fi

echo ""
echo "=== Validação local concluída ==="
echo "Próximo passo: configure suas credenciais AWS e execute:"
echo "  cd $TERRAFORM_DIR"
echo "  cp terraform.tfvars.example terraform.tfvars"
echo "  # edite terraform.tfvars com seu IP"
echo "  terraform init"
echo "  terraform plan -out=tfplan"
