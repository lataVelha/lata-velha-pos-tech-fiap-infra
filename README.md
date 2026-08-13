# lata-velha-pos-tech-fiap-infra

Infraestrutura **base** do projeto **Lata Velha** na AWS (VPC, EKS, ECR, ALB, API Gateway,
Cluster Autoscaler) usando **Terraform >= 1.10** (lock de estado nativo do S3). Compatível com
**AWS Academy (Learner Lab)** — usa a `LabRole` pré-existente.

**Ponto de entrada único:** existe **um só** API Gateway (HTTP API) para tudo. O ALB é
**interno** (sem IP público) e só aceita tráfego do VPC Link desse API Gateway.

Este repo cria só o **"casco"** do API Gateway (API + VPC Link + Stage, sem rotas) — quem usa é
que anexa rota via `terraform_remote_state` nos outputs daqui.

## Sumário

- [Dependências](#dependências)
- [Estrutura](#estrutura)
- [Por que dois módulos Terraform separados (`bootstrap` e `addons`)?](#por-que-dois-módulos-terraform-separados-bootstrap-e-addons)
- [Outputs](#outputs)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
- [Execução local](#execução-local)
  - [Com o script (`apply.sh`)](#com-o-script-applysh)
  - [Manualmente (sem o script)](#manualmente-sem-o-script)

---

## Dependências

Não depende de nenhum outro repo deste projeto.

## Estrutura

```
terraform/
├── apply.sh                  # Orquestrador local (bootstrap + addons)
├── bootstrap/                # Etapa 1: VPC + EKS + ECR
│   └── backend.tf            # Estado em S3: lata-velha/bootstrap/terraform.tfstate
├── addons/                   # Etapa 2: ALB interno + "casco" do API Gateway + Cluster Autoscaler
│   └── backend.tf            # Estado em S3: lata-velha/infra-addons/terraform.tfstate
└── modules/
    ├── vpc/  ├── eks/  ├── alb/                # ALB interno, sem SG aberto pra internet
    ├── app-gateway/                            # API Gateway (HTTP API) + VPC Link — só o casco
    └── cluster-autoscaler/
```

O ALB só libera ingress pro security group dos ENIs do VPC Link (`aws_security_group.vpc_link`,
criado na raiz do `addons` — fora dos módulos `alb`/`app-gateway` de propósito, pra evitar
dependência circular entre os dois). O Stage do API Gateway tem `auto_deploy = true`: qualquer
rota anexada depois é publicada automaticamente, sem reaplicar este repo.

> **Trade-off**: o throttle que existia em `POST /auth/cpf` (10 req/s, 20 de rajada) não existe
> mais — o Stage é criado aqui, e este repo não conhece essa rota no momento em que o cria. Pra
> recuperar rate-limit no login por CPF, usar uma regra WAFv2 (rate-based rule por path).

## Por que dois módulos Terraform separados (`bootstrap` e `addons`)?

Os providers `kubectl`/`helm` do `addons` precisam do endpoint do EKS já existindo — um único
módulo tentaria configurar os providers antes do cluster existir e falharia. Por isso o estado
é dividido em dois, com o `bootstrap` expondo outputs via `TF_VAR_` pro `addons`.

Isso é estrutural (sempre duas chamadas Terraform), mas o `addons` **não depende de mais nenhum
outro repo** — roda logo após o `bootstrap`, no mesmo disparo. `apply.sh` suporta os dois
juntos (padrão) ou separados via `--bootstrap-only`/`--addons-only`.

## Outputs

| Bootstrap | Addons |
| --- | --- |
| `vpc_id`, `vpc_cidr`, `private_subnet_ids` | `app_api_id`, `app_api_execution_arn`, `app_api_endpoint` |
| `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data` | `vpc_link_id`, `alb_listener_arn`, `alb_dns_name` |
| `cluster_security_group_id`, `node_asg_name` | |

## CI/CD (GitHub Actions)

- **PR** → `terraform plan` (bootstrap e addons, sem aplicar)
- **Push em `master`** → aplica de verdade: bootstrap + addons em sequência (`mode: both`)
- **`workflow_dispatch`** → dispara manualmente, com `mode` (`both`/`bootstrap-only`/
  `addons-only`) e `destroy`. **Não combine `destroy: true` com `mode: both`** — a ordem
  inverte no destroy (addons antes do bootstrap); use `addons-only` e depois `bootstrap-only`
  (um guard bloqueia essa combinação com erro claro).

O apply de cada etapa vive em dois workflows reusáveis próprios (`bootstrap.yml`/`addons.yml`,
`on: workflow_call`, aceitam um input `destroy`).

**Secrets/vars**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (AWS
Academy), `AWS_REGION` (var, opcional — default `us-east-1`).

> Na primeira vez, o `bootstrap` ainda não existe — PRs abertas antes do primeiro apply vão
> falhar no `plan` do `addons`. Rode o primeiro apply antes de abrir PRs que dependam dele.

## Execução local

Pré-requisito: `aws configure` (ou `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN`).

### Com o script (`apply.sh`)

```bash
cd terraform
./apply.sh                    # bootstrap + addons, com confirmação interativa
./apply.sh --auto             # sem confirmação
./apply.sh --bootstrap-only   # só VPC + EKS + ECR
./apply.sh --addons-only      # só ALB interno + API Gateway + autoscaler
./apply.sh --destroy          # destroi addons e depois bootstrap
```

### Manualmente (sem o script)

A ordem importa: `bootstrap` primeiro (o `addons` depende dos outputs dele).

```bash
cd terraform/bootstrap
terraform init -backend-config="bucket=<state_bucket>" -backend-config="region=us-east-1"
terraform apply

cd ../addons
export TF_VAR_state_bucket="<state_bucket>"
export TF_VAR_cluster_endpoint=$(terraform -chdir=../bootstrap output -raw cluster_endpoint)
export TF_VAR_cluster_ca_data=$(terraform -chdir=../bootstrap output -raw cluster_certificate_authority_data)
export TF_VAR_cluster_name=$(terraform -chdir=../bootstrap output -raw cluster_name)
terraform init -backend-config="bucket=<state_bucket>" -backend-config="region=us-east-1"
terraform apply
```

Para destruir, ordem inversa: `terraform destroy` no `addons` primeiro, depois no `bootstrap`.
