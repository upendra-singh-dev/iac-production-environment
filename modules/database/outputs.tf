output "endpoint" { value = aws_db_instance.this.endpoint }
output "secret_arn" { value = aws_secretsmanager_secret.db.arn }
output "security_group_id" { value = aws_security_group.db.id }
output "multi_az" { value = aws_db_instance.this.multi_az }
