# ---------------------------------------------------------------------------
# Network: 3 tiers. Only the load balancer is reachable from the Internet.
#   public  subnets -> ALB (HTTPS 443 only)
#   private subnets -> EC2 app host (reachable ONLY from the ALB)
#   data    subnets -> RDS MySQL + PostgreSQL (reachable ONLY from the app host)
# ---------------------------------------------------------------------------
# AZs are pinned explicitly (reproducible: the result never changes silently).
locals {
  azs = var.availability_zones
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "auto-monitor-${var.environment}" }
}

# Lock down the default security group: no inbound, no outbound.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # nothing gets a public IP automatically

  tags = { Name = "public-${count.index}", Tier = "public" }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = { Name = "private-${count.index}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = local.azs[count.index]

  tags = { Name = "data-${count.index}", Tier = "data" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

# NAT lets the private app host pull images from the registry (outbound only).
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Data subnets get NO route to the Internet at all (no association = main RT, local only).

# --- VPC Flow Logs: record accepted/rejected traffic for investigations -------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/auto-monitor/${var.environment}/vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "auto-monitor-${var.environment}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs_write" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_write.json
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn    = aws_iam_role.flow_logs.arn
}

# --- Security groups (least privilege, SG-to-SG references) ------------------
resource "aws_security_group" "alb" {
  name        = "auto-monitor-alb"
  description = "Public entry point: HTTPS only"
  vpc_id      = aws_vpc.main.id

  # Approved exception EXC-01: a public web app must accept HTTPS from anyone.
  #trivy:ignore:AVD-AWS-0107
  #tfsec:ignore:aws-ec2-no-public-ingress-sgr
  ingress {
    description = "HTTPS from the Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to the app host only"
    from_port   = 3000
    to_port     = 4000
    protocol    = "tcp"
    cidr_blocks = [for s in aws_subnet.private : s.cidr_block]
  }
}

resource "aws_security_group" "app" {
  name        = "auto-monitor-app"
  description = "App host: only reachable from the ALB, no SSH (admin via SSM)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Frontend (3000) and WebSocket gateway (4000) from ALB"
    from_port       = 3000
    to_port         = 4000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Approved exception EXC-02: outbound HTTPS needed for registry/LLM/SSM.
  # Next iteration: VPC endpoints + egress proxy allow-list.
  #trivy:ignore:AVD-AWS-0104
  #tfsec:ignore:aws-ec2-no-public-egress-sgr
  egress {
    description = "HTTPS out (registry pull, LLM APIs, SSM) through NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Databases in the data subnets"
    from_port   = 3306
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [for s in aws_subnet.data : s.cidr_block]
  }
}

resource "aws_security_group" "db" {
  name        = "auto-monitor-db"
  description = "Databases: only reachable from the app host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from app host"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "PostgreSQL from app host"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}
