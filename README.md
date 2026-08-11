# lata-velha-pos-tech-fiap-infra

Infraestrutura **base** do projeto **Lata Velha** na AWS (VPC, EKS, ECR, ALB, API Gateway, Cluster Autoscaler) usando **Terraform >= 1.10** (lock de estado nativo do S3). Compatível com **AWS Academy (Learner Lab)** — usa a `LabRole` pré-existente.

**Ponto de entrada único:** existe **um só** API Gateway (HTTP API) para tudo. O ALB é
**interno** (subnets privadas, sem IP público) e só aceita tráfego do VPC Link desse
API Gateway — ninguém acessa o ALB diretamente.

Este repo cria só o **"casco"** do API Gateway (a API HTTP + VPC Link + Stage, sem nenhuma
rota) — nenhuma rota, integração ou authorizer específica vive aqui. Quem anexa isso é quem
usa, via `terraform_remote_state`:

- **Login por CPF + lambda authorizer** (`POST /auth/cpf`, `GET /auth/cpf-openapi.json`, a
  `aws_apigatewayv2_authorizer`) → repo [`lambda`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-lambda)
- **Integração com o ALB + rotas públicas/protegidas do app** → repo [`app`](https://github.com/lataVelha/lata-velha-pos-tech-fiap)
- **Banco de dados (RDS)** → repo [`infra-db`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra-db)

Isso significa que este repo **não depende de nenhum outro** — só precisa do próprio
`bootstrap` já aplicado. `lambda` e `app` é que dependem deste (leem `api_id`/`alb_listener_arn`/
`vpc_link_id` daqui), não o contrário.

## Sumário

- [Estrutura](#estrutura)
  - [Por que o ALB é interno e existe um API Gateway na frente dele?](#por-que-o-alb-é-interno-e-existe-um-api-gateway-na-frente-dele)
  - [Por que dois módulos Terraform separados (`bootstrap` e `addons`)?](#por-que-dois-módulos-terraform-separados-bootstrap-e-addons)
- [Quem consome os outputs deste repo](#quem-consome-os-outputs-deste-repo)
- [De quem este repo depende (e quem depende dele)](#de-quem-este-repo-depende-e-quem-depende-dele)
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
├── addons/                   # Etapa 2: ALB interno + "casco" do API Gateway + Cluster Autoscaler + metrics-server
│   ├── main.tf                # Lê o bootstrap via terraform_remote_state
│   ├── variables.tf
│   ├── outputs.tf             # app_api_id, app_api_execution_arn, app_api_endpoint,
│   │                           # vpc_link_id, alb_listener_arn, alb_dns_name
│   ├── providers.tf            # Providers AWS + kubectl + helm
│   ├── versions.tf
│   └── backend.tf             # Estado em S3: lata-velha/infra-addons/terraform.tfstate
└── modules/
    ├── vpc/
    ├── eks/
    ├── alb/                  # ALB interno — sem SG aberto para a internet
    ├── app-gateway/          # API Gateway (HTTP API) + VPC Link — só o casco, sem rotas
    └── cluster-autoscaler/
```

### Por que o ALB é interno e existe um API Gateway na frente dele?

O ALB não tem mais nenhuma regra de ingress liberada para `0.0.0.0/0`: a única origem
permitida no security group dele é o security group dos ENIs do VPC Link (`aws_security_group.vpc_link`,
criado na raiz do `addons` — ver comentário em `addons/main.tf` sobre por que ele não vive
dentro de nenhum dos dois módulos, para evitar uma dependência circular entre `alb` e
`app-gateway`). O módulo `app-gateway` deste repo cria só o "casco": a API HTTP, o VPC Link e
o Stage (`auto_deploy = true`) — nenhuma rota, integração ou authorizer. Isso é criado por
quem usa, em outro repo, via `terraform_remote_state`:

- **`POST /auth/cpf`** (integração `AWS_PROXY` direto na lambda `auth-cpf`, sem passar pelo
  ALB) e a **lambda authorizer** (`aws_apigatewayv2_authorizer`, tipo `REQUEST`) → criadas no
  repo [`lambda`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-lambda), que lê
  `app_api_id`/`app_api_execution_arn` daqui.
- **Integração `HTTP_PROXY` + `VPC_LINK` com o ALB**, e as rotas públicas
  (`/actuator/health/**`, `/swagger-ui.html`, `/auth/**`, etc — espelham os `.permitAll()` do
  `SecurityConfig.java`) e protegidas (`ANY /`, `ANY /{proxy+}`, exigindo o JWT via a
  authorizer do `lambda`) → criadas no repo
  [`app`](https://github.com/lataVelha/lata-velha-pos-tech-fiap), que lê `app_api_id`/
  `alb_listener_arn`/`vpc_link_id` (deste repo) e `jwt_authorizer_id` (do repo `lambda`).

Auto_deploy no Stage garante que qualquer rota anexada depois (por `lambda` ou `app`) é
publicada automaticamente, sem precisar reaplicar este repo.

> **Trade-off**: o throttle específico que existia em `POST /auth/cpf` (10 req/s sustentado,
> 20 de rajada) não existe mais — o `aws_apigatewayv2_stage` é criado aqui, e este repo não
> conhece a rota do `lambda` no momento em que o cria. Se precisar de rate-limit no login por
> CPF, use uma regra WAFv2 (rate-based rule por path) em vez do `route_settings` do stage.

### Por que dois módulos Terraform separados (`bootstrap` e `addons`)?

Os providers `kubectl` e `helm` do módulo `addons` precisam do endpoint do cluster EKS para
serem inicializados — e esse endpoint só existe após o `bootstrap` criar o cluster. Um único
módulo tentaria configurar os providers antes do EKS existir e falharia. Por isso o estado é
dividido em dois: o `bootstrap` expõe seus outputs como variáveis de ambiente (`TF_VAR_`) para
o `addons`, já que blocos `provider` não usam `data sources` para a própria configuração.

Isso é estrutural — sempre vai precisar de duas chamadas Terraform pra este repo. Mas
diferente de antes, o `addons` **não depende de mais nenhum outro repo** (nem `lambda`, nem
`app`): ele roda logo em seguida do `bootstrap`, no mesmo disparo, sem esperar nada.
`apply.sh` suporta rodar os dois juntos (modo padrão) ou separados via
`--bootstrap-only`/`--addons-only` (ver [Execução local](#execução-local)).

## Quem consome os outputs deste repo

| Consumidor | O que lê | Para quê |
| --- | --- | --- |
| `infra-db` | `vpc_id`, `vpc_cidr`, `private_subnet_ids` (bootstrap) | Provisionar o RDS na mesma VPC |
| `lambda` | `vpc_id`, `private_subnet_ids` (bootstrap); `app_api_id`, `app_api_execution_arn` (addons) | Rodar a lambda de autenticação por CPF na mesma VPC do RDS; anexar `POST /auth/cpf` + a authorizer no API Gateway |
| `app` | nome do cluster EKS e do repositório ECR via **AWS CLI** (não Terraform state); `app_api_id`, `alb_listener_arn`, `vpc_link_id` (addons) | Build/push da imagem, deploy; anexar a integração com o ALB + as rotas públicas/protegidas |
| **você** | `app_api_endpoint` (addons) — mas as rotas de verdade só existem depois de `lambda`/`app` também terem aplicado | Base da URL pública da aplicação — não mais `alb_dns_name` |

O nome do cluster (`lata-velha-eks`) e do repositório ECR (`lata-velha`) seguem convenção fixa
(`project_name` = `lata-velha`), então o repo `app` não precisa ler o Terraform state do
`bootstrap` — só precisa saber os nomes (mas já lê o state do `addons`, pro API Gateway).

## De quem este repo depende (e quem depende dele)

O `bootstrap` não depende de nenhum outro repo. O `addons` também não — diferente de antes,
ele **não lê mais o remote state do `lambda`**: cria só o "casco" do API Gateway, sem rota
nenhuma. Quem depende deste repo agora são `lambda` e `app` (ambos leem o `api_id` daqui pra
anexar suas próprias rotas) — a relação de dependência é a oposta da versão anterior deste
repo, onde `addons` é que lia o state do `lambda`.

## CI/CD (GitHub Actions)

- **PR para `master`** → `terraform plan` (bootstrap e addons — addons lê os outputs reais do
  último apply do bootstrap para inicializar os providers, sem aplicar nada)
- **Push em `master`** → só roda a CI (o `plan` acima é só em PR; push não aplica nada de
  verdade)
- **`workflow_dispatch`** (Actions → Run workflow) → o deploy de verdade, com um input `mode`
  (`both`/`bootstrap-only`/`addons-only`) — `both` roda bootstrap e addons em sequência, num
  disparo só, sem esperar mais nada

O apply de cada etapa vive em dois workflows **reusáveis** próprios
(`.github/workflows/bootstrap.yml` e `addons.yml`, `on: workflow_call`) — o `main.yml` deste
repo só os chama (`uses: ./.github/workflows/...`). É a mesma definição que o mono repo chama
de fora (`uses: lataVelha/lata-velha-pos-tech-fiap-infra/.github/workflows/...@master`) — nenhuma
lógica de deploy é duplicada entre os dois repos. Os dois workflows também aceitam um input
`destroy` (mesmo padrão do `--destroy` local) pra desfazer.

### Secrets/vars necessários no repositório

| Nome | Tipo | Descrição |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | secret | Credencial AWS |
| `AWS_SECRET_ACCESS_KEY` | secret | Credencial AWS |
| `AWS_SESSION_TOKEN` | secret | Necessário no AWS Academy (roles temporárias) |
| `AWS_REGION` | var (opcional) | Região AWS — se não cadastrar, usa `us-east-1` como default |

> A primeira vez que o pipeline roda, o `bootstrap` ainda não existe — o job `plan` de PRs
> abertas antes do primeiro apply vai falhar ao ler o output do bootstrap. Rode o primeiro
> `apply` (Run workflow com `mode: both`, ou `./apply.sh --auto` local) antes de abrir PRs que
> dependam do `addons`.

## Execução local

Pré-requisito, para as duas formas abaixo: `aws configure` (ou `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` no ambiente).

### Com o script (`apply.sh`)

Modo padrão (bootstrap + addons juntos) já funciona num deploy do zero — `addons` não depende
de mais nenhum outro repo:

```bash
cd terraform
./apply.sh              # bootstrap + addons, com confirmação interativa
./apply.sh --auto       # sem confirmação
./apply.sh --destroy    # destroi addons e depois bootstrap, com confirmação
./apply.sh --destroy --auto # destroi sem confirmação
```

As flags `--bootstrap-only`/`--addons-only` continuam disponíveis se quiser rodar cada etapa
separada (por exemplo, pra depurar só uma delas):

```bash
./apply.sh --bootstrap-only         # só VPC + EKS + ECR
./apply.sh --addons-only            # só ALB interno + API Gateway + autoscaler
```

O `apply.sh` da raiz do mono repo já roda isso na posição certa do pipeline completo (logo
após o bootstrap, antes de `infra-db`/`lambda`/`app`).

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
