# Documentação — AWS Production VPC Architecture

Bem-vindo à documentação técnica do projeto **AWS Production VPC Architecture**.

## Documentos disponíveis

| Documento | Descrição | Público-alvo |
|---|---|---|
| [📐 Documentação de Arquitetura](arquitetura/documentacao-arquitetura.md) | Detalhes técnicos da arquitetura — topologia, componentes, decisões de design, módulos Terraform | Engenheiros de infraestrutura, revisores de arquitetura |
| [📋 Runbook Operacional](runbooks/runbook-vpc-operations.md) | Procedimentos passo a passo para deploy, destroy, troubleshooting e monitoramento | SREs, DevOps engineers, on-call |
| [⚙️ Variáveis de Ambiente](config/variaveis-de-ambiente.md) | Templates de `terraform.tfvars` para dev, staging e prod; configuração de backend e CI/CD | Todos os contribuidores |

---

## Início rápido

1. Leia a [Documentação de Arquitetura](arquitetura/documentacao-arquitetura.md) para entender a topologia de rede
2. Configure suas credenciais AWS com `aws configure`
3. Faça o bootstrap do remote state (seção 1 do [Runbook](runbooks/runbook-vpc-operations.md))
4. Copie o template de [Variáveis de Ambiente](config/variaveis-de-ambiente.md) para o ambiente desejado
5. Execute `terraform init && terraform plan && terraform apply`

---

