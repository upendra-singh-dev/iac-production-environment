data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Blocks the confused-deputy path on a leaked role ARN.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${var.account_id}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

# EXECUTION role: the agent, pre-start. The managed
# AmazonECSTaskExecutionRolePolicy is deliberately NOT attached - it grants ecr
# and logs on "*".
resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrAuthToken"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # no resource form exists; the pull is scoped below
  }
  statement {
    sid       = "PullThisRepoOnly"
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "WriteOwnLogsOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
  statement {
    sid       = "ReadDbSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "execution"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# TASK role: the running app. Assets bucket only - deliberately no
# secretsmanager, so a compromised process cannot re-read the credential.
resource "aws_iam_role" "task" {
  name               = "${var.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "AssetObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.assets_bucket_arn}/*"]
  }
  statement {
    sid       = "AssetListing"
    actions   = ["s3:ListBucket"]
    resources = [var.assets_bucket_arn]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "task"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}
