resource "aws_lb" "this" {
  name                       = var.name
  load_balancer_type         = "application"
  internal                   = false
  subnets                    = var.public_subnet_ids
  security_groups            = [aws_security_group.alb.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = true
}

resource "aws_lb_target_group" "app" {
  name                 = "${var.name}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # awsvpc tasks register by ENI address
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = local.health_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# The certificate is issued outside this stack and passed in: it outlives any
# single environment and its DNS validation is a one-off. The runbook covers it.
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_ecs_service" "app" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count

  network_configuration {
    subnets          = var.private_subnet_ids # tasks never sit in a public subnet
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port   = var.container_port
  }

  # COST TRADE-OFF: Spot for the bulk, one on-demand task as a floor so a
  # reclamation cannot take the service to zero.
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = local.spot_weight
  }
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = local.ondemand_weight
    base              = var.ondemand_base
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true # a bad image rolls back instead of draining the service
  }
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 60
  wait_for_steady_state              = true

  depends_on = [aws_lb_listener.https]
}
