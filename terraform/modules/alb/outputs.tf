output "dns_name" {
  description = "DNS name do ALB"
  value       = aws_lb.this.dns_name
}

output "arn" {
  description = "ARN do ALB"
  value       = aws_lb.this.arn
}
