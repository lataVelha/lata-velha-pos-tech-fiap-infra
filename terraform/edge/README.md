# Edge — API Gateway compartilhado

Este stack é o **dono único** da borda HTTP depois do cutover do `app`:

- integração `HTTP_PROXY` do API Gateway compartilhado com o listener do ALB;
- rotas públicas (health, swagger, `/auth/*`, aprovação de orçamento);
- `ANY /` e `ANY /{proxy+}` protegidas pela authorizer do repo `lambda`.

O roteamento por path para `os-service`, `inventory-service` e `app` fica no
ALB (`infra/terraform/addons`), não aqui. O `billing-service` mantém o NLB/API
Gateway próprio para o webhook do Mercado Pago.

## Dependências

1. `infra/terraform/bootstrap` (VPC + EKS)
2. `infra/terraform/addons` (API Gateway + ALB + target groups + listener rules)
3. `lambda` (authorizer JWT)

## Uso

```bash
./apply.sh            # apply
./apply.sh --destroy  # destroy
```

O `apply.sh` resolve o bucket `lata-velha-tfstate-<account>` e passa
`TF_VAR_state_bucket`/`TF_VAR_region`.

## State

`lata-velha/edge/terraform.tfstate` no bucket de state do projeto.

## Cutover

Antes deste stack existir, as rotas eram criadas pelo `app`. Para evitar
conflito (`Route already exists`), o apply do `app` com o código novo remove
as rotas antigas e, na sequência, este stack as recria.
