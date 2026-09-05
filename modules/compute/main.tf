resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = local.log_retention_days
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "disabled" # ~$3/mo of custom metrics; not in budget
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64" # Graviton: ~20% cheaper than X86_64
  }

  container_definitions = jsonencode([{
    name                   = "api"
    image                  = var.image
    essential              = true
    user                   = "10001:10001" # requirement 2: never root
    readonlyRootFilesystem = true
    linuxParameters = {
      initProcessEnabled = true
      capabilities       = { drop = ["ALL"] }
    }
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "ASSETS_BUCKET", value = var.assets_bucket_name },
      { name = "AWS_REGION", value = var.region },
    ]
    # Resolved by the agent from Secrets Manager; never plaintext here.
    secrets     = [{ name = "DATABASE_URL", valueFrom = "${var.db_secret_arn}:url::" }]
    mountPoints = [{ sourceVolume = "tmp", containerPath = "/tmp", readOnly = false }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "api"
      }
    }
  }])

  volume { name = "tmp" } # readonlyRootFilesystem still needs scratch
}

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public HTTPS"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "HTTP, redirected at the listener"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.tasks.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  description                  = "To tasks"
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "Tasks: ALB ingress only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-tasks" }
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
  description                  = "From ALB"
}

# Open egress: image pulls, Secrets Manager, logs. Narrowing to prefix lists
# is the next hardening step, named in the runbook rather than claimed.
resource "aws_vpc_security_group_egress_rule" "tasks_out" {
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Via NAT and the S3 endpoint"
}
