resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = var.private_subnet_ids # private only: requirement 3
}

resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Postgres from the ECS tasks only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-db" }
}

# Referencing the task SG, not a CIDR: nothing else in the VPC can reach it.
resource "aws_vpc_security_group_ingress_rule" "db_from_tasks" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = var.app_security_group_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from ECS tasks"
}

resource "random_password" "db" {
  length  = 32
  special = false # avoids shell/URI escaping bugs in connection strings
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/database"
  recovery_window_in_days = 7
}

# Lives only in state and Secrets Manager: never a variable, never in tfvars.
resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.db.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
    url      = "postgres://${var.master_username}:${random_password.db.result}@${aws_db_instance.this.endpoint}/${var.db_name}"
  })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-pg"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100 # autoscale headroom; billed only if used
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false # requirement 3
  port                   = 5432

  # COST TRADE-OFF: single-AZ. Multi-AZ alone would breach the cap. The
  # consequence is quantified in the runbook; PITR is what makes it recoverable.
  multi_az                  = var.multi_az
  backup_retention_period   = var.backup_retention_days # enables PITR
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot     = true
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-pg-final"

  performance_insights_enabled = false # chargeable beyond 7 days
  auto_minor_version_upgrade   = true

  tags = { Name = "${var.name}-pg", BackupPlan = "pitr-${var.backup_retention_days}d" }
}
