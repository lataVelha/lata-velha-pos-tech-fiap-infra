# lata-velha-pos-tech-fiap-infra

Infraestrutura **base** do projeto **Lata Velha** na AWS (VPC, EKS, ECR, ALB, API Gateway, Cluster Autoscaler) usando **Terraform >= 1.10** (lock de estado nativo do S3). Compatível com **AWS Academy (Learner Lab)** — usa a `LabRole` pré-existente.

**Ponto de entrada único:** existe **um só** API Gateway (HTTP API) para tudo. O ALB é
**interno** (subnets privadas, sem IP público) e só aceita tráfego do VPC Link desse
API Gateway — ninguém acessa o ALB diretamente. Todo tráfego externo, incluindo o login por
CPF (`POST /auth/cpf`, integrado direto numa lambda do repo `lambda`), passa por
`app_api_endpoint` (ver [outputs](#quem-consome-os-outputs-deste-repo)). As rotas do app que
exigem autenticação passam antes por uma **lambda authorizer** (também do repo `lambda`), que
valida o JWT antes da requisição chegar ao ALB — duplicando na borda a mesma checagem que o
`JwtDecoder` do app já faz.

Este repo cuida só da infraestrutura compartilhada do cluster. O que é específico de cada domínio vive em outro lugar:

- **Banco de dados (RDS)** → repo [`infra-db`](https://github.com/lataVelha/lata-velha-pos-tech-fiap-infra-db)
- **Deploy da aplicação** (Deployment/Service/ConfigMap/Secret/HPA/PDB) → repo [`app`](https://github.com/lataVelha/lata-velha-pos-tech-fiap)

## Sumário

- [Estrutura](#estrutura)
  - [Por que o ALB é interno e existe um API Gateway na frente dele?](#por-que-o-alb-é-interno-e-existe-um-api-gateway-na-frente-dele)
  - [Por que dois módulos Terraform separados (`bootstrap` e `addons`)?](#por-que-dois-módulos-terraform-separados-bootstrap-e-addons)
- [Quem consome os outputs deste repo](#quem-consome-os-outputs-deste-repo)
- [De quem o `addons` depende](#de-quem-o-addons-depende)
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
├── addons/                   # Etapa 2: ALB interno + API Gateway + Cluster Autoscaler + metrics-server
│   ├── main.tf                # Lê o bootstrap via terraform_remote_state
│   ├── variables.tf
│   ├── outputs.tf             # app_api_endpoint, auth_cpf_endpoint (URL pública), alb_dns_name (interno)
│   ├── providers.tf            # Providers AWS + kubectl + helm
│   ├── versions.tf
│   └── backend.tf             # Estado em S3: lata-velha/infra-addons/terraform.tfstate
└── modules/
    ├── vpc/
    ├── eks/
    ├── alb/                  # ALB interno — sem SG aberto para a internet
    ├── app-gateway/          # API Gateway (HTTP API) + VPC Link -> ALB
    └── cluster-autoscaler/
```

### Por que o ALB é interno e existe um API Gateway na frente dele?

O ALB não tem mais nenhuma regra de ingress liberada para `0.0.0.0/0`: a única origem
permitida no security group dele é o security group dos ENIs do VPC Link (`aws_security_group.vpc_link`,
criado na raiz do `addons` — ver comentário em `addons/main.tf` sobre por que ele não vive
dentro de nenhum dos dois módulos, para evitar uma dependência circular entre `alb` e
`app-gateway`). O API Gateway (`módulo app-gateway`) expõe uma integração privada
(`HTTP_PROXY` + `VPC_LINK`) para o listener do ALB — repassa método/path/header/body sem
transformação, então nada muda do ponto de vista do app.

As rotas são de três tipos:

- **`POST /auth/cpf`**: integração `AWS_PROXY` direto na lambda `auth-cpf` (repo `lambda`) —
  não passa pelo ALB. Pública de propósito: é o endpoint que *emite* o token, não dá pra
  exigir token pra acessá-lo.
- **Públicas via ALB** (sem authorizer): `/actuator/health/**`, `/swagger-ui.html`,
  `/swagger-ui/**`, `/v3/api-docs/**`, `/v3/api-docs.yaml`, `/auth/**` (login por email/senha
  do app), `POST /ordens-servico/{id}/aprovacao-orcamento` — espelham exatamente os
  `.permitAll()` do `SecurityConfig.java` do app.
- **Protegidas via ALB** (`ANY /` e `ANY /{proxy+}`): exigem um JWT válido, checado por uma
  **lambda authorizer** do repo `lambda` (`aws_apigatewayv2_authorizer`, tipo `REQUEST`,
  `enable_simple_responses`). Ela só verifica assinatura RS256 + issuer + expiração — a
  mesma chave pública compartilhada com o app — e **não decide por role**; isso continua
  sendo responsabilidade exclusiva do `SecurityConfig` do app. É uma duplicação
  intencional: rejeita cedo requisições sem token válido, sem gastar um hop até o ALB/pod.

Esse é o motivo do `addons` precisar de quatro outputs do repo `lambda` (via
`terraform_remote_state`): `jwt_authorizer_invoke_arn`/`jwt_authorizer_function_name` (a
authorizer) e `auth_cpf_invoke_arn`/`auth_cpf_function_name` (a rota de login) — ver
[ordem do pipeline](#quem-consome-os-outputs-deste-repo).

### Por que dois módulos Terraform separados (`bootstrap` e `addons`)?

Os providers `kubectl` e `helm` do módulo `addons` precisam do endpoint do cluster EKS para
serem inicializados — e esse endpoint só existe após o `bootstrap` criar o cluster. Um único
módulo tentaria configurar os providers antes do EKS existir e falharia. Por isso o estado é
dividido em dois: o `bootstrap` expõe seus outputs como variáveis de ambiente (`TF_VAR_`) para
o `addons`, já que blocos `provider` não usam `data sources` para a própria configuração.

Essa divisão também é o que permite intercalar o repo `lambda` no meio do pipeline: como o
`addons` (API Gateway) precisa do ARN da lambda authorizer, e o `bootstrap` (VPC/EKS) não
precisa de nada do `lambda`, a ordem completa é **`infra bootstrap` → `infra-db` → `lambda`
→ `infra addons` → `app`** — não dá pra rodar `bootstrap`+`addons` como um bloco só antes do
`lambda`, como acontecia antes do API Gateway existir. `apply.sh` suporta isso via
`--bootstrap-only`/`--addons-only` (ver [Execução local](#execução-local)).

## Quem consome os outputs deste repo

| Consumidor | O que lê | Para quê |
| --- | --- | --- |
| `infra-db` | `vpc_id`, `vpc_cidr`, `private_subnet_ids` (bootstrap) | Provisionar o RDS na mesma VPC |
| `lambda` | `vpc_id`, `private_subnet_ids` (bootstrap) | Rodar a lambda de autenticação por CPF na mesma VPC do RDS |
| `app` (CI/CD) | nome do cluster EKS e do repositório ECR — via **AWS CLI**, não via Terraform state (ver `app/README.md`) | Fazer login no ECR, build/push da imagem e configurar `kubectl`/deploy |
| **você** | `app_api_endpoint`/`auth_cpf_endpoint` (addons) | É essa a URL pública da aplicação agora — não mais `alb_dns_name` |

O nome do cluster (`lata-velha-eks`) e do repositório ECR (`lata-velha`) seguem convenção fixa
(`project_name` = `lata-velha`), então o repo `app` não precisa ler o Terraform state deste
repo — só precisa saber os nomes. Isso mantém os pipelines dos três repos desacoplados.

## De quem o `addons` depende

Diferente do `bootstrap` (que não depende de nenhum outro repo), o `addons` **lê o remote
state do repo `lambda`** — os ARNs das duas lambdas (`jwt-authorizer` e `auth-cpf`) — para
anexar a authorizer nas rotas protegidas e criar a integração de `POST /auth/cpf`. Isso só
existe porque as duas rodam como função Lambda, não como um `data source` estático — é a
exceção à regra de que este repo não depende de nenhum outro. Se o `lambda` nunca foi
aplicado, `terraform apply` no `addons` falha ao ler esse state (erro de "key not found" no S3).

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
> antes de abrir PRs que dependam do `addons`. Além disso, desde que o API Gateway existe,
> o `addons` também só aplica depois do repo `lambda` já ter sido aplicado (ver
> [De quem o `addons` depende](#de-quem-o-addons-depende)).

## Execução local

Pré-requisito, para as duas formas abaixo: `aws configure` (ou `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` no ambiente).

### Com o script (`apply.sh`)

Num deploy do zero, `bootstrap` e `addons` **não** podem rodar como um bloco só — o `addons`
precisa do repo `lambda` já aplicado antes dele. Use as flags para intercalar:

```bash
cd terraform
./apply.sh --bootstrap-only         # [1] VPC + EKS + ECR
# ... aplique infra-db e lambda aqui ...
./apply.sh --addons-only            # [2] ALB interno + API Gateway + autoscaler
```

O modo padrão (sem flags, os dois juntos) só funciona se o `lambda` **já tiver sido aplicado
antes** — serve para reaplicar tudo depois que a stack inteira já existe:

```bash
./apply.sh              # bootstrap + addons, com confirmação interativa
./apply.sh --auto       # sem confirmação
./apply.sh --destroy    # destroi addons e depois bootstrap, com confirmação
./apply.sh --destroy --auto # destroi sem confirmação
```

O `apply.sh` da raiz do mono repo já faz essa intercalação automaticamente — prefira ele para um deploy completo do zero.

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
