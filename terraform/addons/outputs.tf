output "alb_dns_name" {
  description = "DNS name do ALB (URL publica da aplicacao: http://<alb_dns_name>)"
  value       = module.alb.dns_name
}
