terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}


data "aws_availability_zones" "available" {
  state = "available"
}

# VPC Configuration (using default VPC for simplicity)
data "aws_vpc" "main" {
  default = true
}

data "aws_internet_gateway" "main" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

# Get default subnets
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# Create private subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = data.aws_vpc.main.id
  cidr_block        = "172.31.${count.index + 100}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name = "devops-private-subnet-${count.index + 1}"
  }
}

# NAT Gateway for private subnets
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "devops-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = tolist(data.aws_subnets.public.ids)[0]
  
  tags = {
    Name = "devops-nat"
  }
}

# Route table for private subnets
resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  
  tags = {
    Name = "devops-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "devops-alb-"
  vpc_id      = data.aws_vpc.main.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "devops-alb-sg"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "devops-ecs-tasks-"
  vpc_id      = data.aws_vpc.main.id
  
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "devops-ecs-tasks-sg"
  }
}

# ECR Repositories - Terraform creates these
resource "aws_ecr_repository" "backend" {
  name         = "devops-backend"
  force_delete = true

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name = "devops-backend"
  }
}

resource "aws_ecr_repository" "frontend" {
  name         = "devops-frontend"
  force_delete = true

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name = "devops-frontend"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "devops-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.public.ids
  
  tags = {
    Name = "devops-alb"
  }
}

# ALB Target Groups
resource "aws_lb_target_group" "frontend" {
  name        = "devops-frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"
  
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "devops-frontend-tg"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "devops-backend-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "devops-backend-tg"
  }
}

# ALB Listeners
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "backend" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
  
  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "devops-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "devops-cluster"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/devops-backend"
  retention_in_days = 7

  tags = {
    Name = "devops-backend-logs"
  }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/devops-frontend"
  retention_in_days = 7

  tags = {
    Name = "devops-frontend-logs"
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "devops-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "devops-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "devops-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "devops-ecs-task-role"
  }
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "devops-ecs-task-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.app_secrets.arn
      }
    ]
  })
}

# Secrets Manager
resource "aws_secretsmanager_secret" "app_secrets" {
  name = "devops/app-secrets-v4"

  tags = {
    Name = "devops-app-secrets-v4"
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    database_url = "your-database-connection-string"
    api_key      = "your-api-key"
  })
}