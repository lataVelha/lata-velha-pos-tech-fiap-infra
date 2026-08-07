output "dns_name" {
  description = "DNS name do ALB"
  value       = aws_lb.this.dns_name
}

output "arn" {
  description = "ARN do ALB"
  value       = aws_lb.this.arn
}

output "listener_arn" {
  description = "ARN do listener HTTP:80 — usado como integration_uri pelo modulo app-gateway"
  value       = aws_lb_listener.http.arn
}

output "security_group_id" {
  description = "Security group do ALB"
  value       = aws_security_group.this.id
}
