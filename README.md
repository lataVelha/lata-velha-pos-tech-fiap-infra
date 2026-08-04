# lata-velha-pos-tech-fiap-infra

Infraestrutura **base** do projeto **Lata Velha** na AWS (VPC, EKS, ECR, ALB, Cluster Autoscaler) usando **Terraform >= 1.10** (lock de estado nativo do S3). Compatível com **AWS Academy (Learner Lab)** — usa a `LabRole` pré-existente.

Este repo cuida só da infraestrutura compartilhada do cluster. O que é específico de cada domínio vive em outro lugar:

- **Banco de dados (RDS)** → repo [`infra-db`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra-db)
- **Deploy da aplicação** (Deployment/Service/ConfigMap/Secret/HPA/PDB) → repo [`app`](https://github.com/lataVelha/lata-velha-pos-tech-fiap)

## Sumário

- [Estrutura](#estrutura)
  - [Por que dois módulos Terraform separados (`bootstrap` e `addons`)?](#por-que-dois-módulos-terraform-separados-bootstrap-e-addons)
- [Quem consome os outputs deste repo](#quem-consome-os-outputs-deste-repo)
- [CI/CD (GitHub Actions)](#cicd-github-actions)
  - [Secrets/vars necessários no repositório](#secretsvars-necessários-no-repositório)
- [Execução local](#execução-local)
  - [Com o script (`apply.sh`)](#com-o-script-applysh)
  - [Manualmente (sem o script)](#manualmente-sem-o-script)

---

## Estrutura

```
terraform/
├── apply.sh                  # Orquestrador local (bootstrap + addons)
├── bootstrap/                # Etapa 1: VPC + EKS + ECR
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf            # Expõe endpoints/IDs para addons, infra-db e app
│   ├── providers.tf
│   ├── versions.tf
│   └── backend.tf            # Estado em S3: lata-velha/bootstrap/terraform.tfstate
├── addons/                   # Etapa 2: ALB + Cluster Autoscaler + metrics-server
│   ├── main.tf                # Lê o bootstrap via terraform_remote_state
│   ├── variables.tf
│   ├── outputs.tf             # alb_dns_name
│   ├── providers.tf            # Providers AWS + kubectl + helm
│   ├── versions.tf
│   └── backend.tf             # Estado em S3: lata-velha/infra-addons/terraform.tfstate
└── modules/
    ├── vpc/
    ├── eks/
    ├── alb/
    └── cluster-autoscaler/
```

### Por que dois módulos Terraform separados (`bootstrap` e `addons`)?

Os providers `kubectl` e `helm` do módulo `addons` precisam do endpoint do cluster EKS para
serem inicializados — e esse endpoint só existe após o `bootstrap` criar o cluster. Um único
módulo tentaria configurar os providers antes do EKS existir e falharia. Por isso o estado é
dividido em dois: o `bootstrap` expõe seus outputs como variáveis de ambiente (`TF_VAR_`) para
o `addons`, já que blocos `provider` não usam `data sources` para a própria configuração.

## Quem consome os outputs deste repo

| Consumidor | O que lê | Para quê |
| --- | --- | --- |
| `infra-db` | `vpc_id`, `vpc_cidr`, `private_subnet_ids` (bootstrap) | Provisionar o RDS na mesma VPC |
| `app` (CI/CD) | nome do cluster EKS e do repositório ECR — via **AWS CLI**, não via Terraform state (ver `app/README.md`) | Fazer login no ECR, build/push da imagem e configurar `kubectl`/deploy |

O nome do cluster (`lata-velha-eks`) e do repositório ECR (`lata-velha`) seguem convenção fixa
(`project_name` = `lata-velha`), então o repo `app` não precisa ler o Terraform state deste
repo — só precisa saber os nomes. Isso mantém os pipelines dos três repos desacoplados.

## CI/CD (GitHub Actions)

- **PR para `main`** → `terraform plan` (bootstrap e addons — addons lê os outputs reais do
  último apply do bootstrap para inicializar os providers, sem aplicar nada)
- **Push em `main`** → `terraform apply` do bootstrap, depois do addons

### Secrets/vars necessários no repositório

| Nome | Tipo | Descrição |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | secret | Credencial AWS |
| `AWS_SECRET_ACCESS_KEY` | secret | Credencial AWS |
| `AWS_SESSION_TOKEN` | secret | Necessário no AWS Academy (roles temporárias) |
| `AWS_REGION` | var | Região AWS (ex: `us-east-1`) |

> A primeira vez que o pipeline roda em `main`, o `bootstrap` ainda não existe — o job
> `plan` de PRs abertos antes do primeiro apply em `main` vai falhar ao ler o output do
> bootstrap. Rode o primeiro `apply` (push direto em `main` ou `./apply.sh --auto` local)
> antes de abrir PRs que dependam do `addons`.

## Execução local

Pré-requisito, para as duas formas abaixo: `aws configure` (ou `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` no ambiente).

### Com o script (`apply.sh`)

Forma recomendada — resolve o bucket de estado automaticamente, cria-o se ainda não existir e aplica `bootstrap` e `addons` na ordem certa (com os outputs do primeiro injetados no segundo).

```bash
cd terraform
./apply.sh              # bootstrap + addons, com confirmação interativa
./apply.sh --auto       # sem confirmação
./apply.sh --destroy    # destroi addons e depois bootstrap, com confirmação
./apply.sh --destroy --auto # destroi sem confirmação
```

### Manualmente (sem o script)

Útil para depurar um `plan`/`apply` específico ou quando o bucket de estado já existe. A ordem importa: `bootstrap` primeiro (o `addons` depende dos outputs dele).

```bash
cd terraform/bootstrap
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="region=us-east-1"
terraform plan
terraform apply

cd ../addons
export TF_VAR_state_bucket="<state_bucket>"
export TF_VAR_cluster_endpoint=$(terraform -chdir=../bootstrap output -raw cluster_endpoint)
export TF_VAR_cluster_ca_data=$(terraform -chdir=../bootstrap output -raw cluster_certificate_authority_data)
export TF_VAR_cluster_name=$(terraform -chdir=../bootstrap output -raw cluster_name)
terraform init \
  -backend-config="bucket=<state_bucket>" \
  -backend-config="region=us-east-1"
terraform plan
terraform apply
```

Para destruir, na ordem inversa: `terraform destroy` no `addons` primeiro, depois no `bootstrap`.
