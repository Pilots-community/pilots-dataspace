data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # Execution role can read any Secrets Manager secret whose name starts with
  # name_prefix (covers DB password + every per-service config secret created
  # by service modules) plus the optional GHCR pull-credentials secret.
  prefixed_secret_arn_pattern = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.name_prefix}-*"

  execution_secret_resources = compact([
    local.prefixed_secret_arn_pattern,
    var.ghcr_credentials_secret_arn,
  ])
}

# ------------------------------------------------------------------------
# Execution role: pulls images, writes logs, materialises ECS `secrets`.
# ------------------------------------------------------------------------
resource "aws_iam_role" "execution" {
  name = "${var.name_prefix}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "kms:Decrypt",
      ]
      Resource = local.execution_secret_resources
    }]
  })
}

# ------------------------------------------------------------------------
# Task role: used by the *application* once running. EDC services don't call
# AWS APIs directly, so this role is intentionally bare — but split from the
# execution role so future per-service permissions (e.g. seeder writes to EFS,
# or a future EDC AWS-S3 data-plane extension) attach to the right principal.
# ------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name = "${var.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
