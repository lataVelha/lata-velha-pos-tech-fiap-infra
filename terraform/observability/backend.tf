terraform {
  backend "s3" {
    key          = "lata-velha/observability/terraform.tfstate"
    use_lockfile = true
  }
}
