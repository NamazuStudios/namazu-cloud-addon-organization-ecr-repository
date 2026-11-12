# Per-organization ECR repository in Namazu's SHARED hosting AWS account —
# tenant isolation does not come from account boundaries here, so this addon
# carries the ownership explicitly:
#
#   <organization-id>/<repository-name>     (the org's db id as the prefix)
#   tags: cloud.namazustudios.com/organization_id (+ ManagedBy)
#   pull: PER-NAMESPACE — the repository policy grants pull ONLY to the
#         installing tenant's principals (node role + named extras)
#   push: one OIDC-trusted role per input GitHub repository, scoped to THIS
#         repo's ARN, trust pinned to main only (decided 2026-11-12)
#
# IMMUTABLE tag mutability keeps the digest-pin workflow 1:1; AES256 (not
# KMS) keeps the node-role IAM story unchanged; the lifecycle keeps pinned
# digests + rollback headroom and expires untagged debris fast.
#
# The two author rules (contract, stated inline so consumers inherit them):
#  1. NEVER re-declare a variable from 20-variables.tf — those are the
#     tenant contract, not yours. Addon-semantics inputs live in variables.tf.
#  2. NEVER couple to another addon except through its outputs (via
#     `$addon.<id>.<variant>.<output>` bindings in manifest.yaml).

locals {
  repository_name = "${var.organization_id}/${var.repository_name}"

  oidc_provider_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : data.aws_iam_openid_connect_provider.github[0].arn

  # The per-namespace read boundary: the tenant's node role plus any named
  # extra principals (IRSA roles of the target namespace).
  reader_role_arns = concat(
    ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.karpenter_node_role_name}"],
    var.extra_reader_role_arns,
  )

  sanitize = replace(replace(lower(var.repository_name), "/[^a-z0-9-]/", "-"), "/-+/", "-")
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == "" ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_ecr_repository" "repo" {
  name = local.repository_name

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # AES256, not KMS: KMS-encrypted layers would put kms:Decrypt on every node
  # pull; AES256 keeps the node-role IAM story unchanged.
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(
    { "ManagedBy" = "terraform" },
    var.product_sku != null ? { "cloud.namazustudios.com/product_sku" = var.product_sku } : {},
  )
}

# Digest-pin-friendly lifecycle: pinned digests + rollback headroom stay;
# untagged debris expires fast.
resource "aws_ecr_lifecycle_policy" "repo" {
  repository = aws_ecr_repository.repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged (IMMUTABLE-rejected overwrite debris) after 14 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 14
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the last 20 tagged images (pinned digests + rollback headroom)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = 20
        }
        action = { type = "expire" }
      }
    ]
  })
}

# PER-NAMESPACE read enforcement (decided 2026-11-12): only the installing
# tenant's principals get pull.
data "aws_iam_policy_document" "pull" {
  statement {
    sid    = "TenantNamespacePull"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = local.reader_role_arns
    }
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
  }
}

resource "aws_ecr_repository_policy" "pull" {
  repository = aws_ecr_repository.repo.name
  policy     = data.aws_iam_policy_document.pull.json
}

# CI push wiring: one role per input GitHub repository, trusted by that
# repo's OIDC subject (MAIN ONLY), scoped to THIS repo's ARN.
resource "aws_iam_role" "push" {
  for_each = toset(var.github_repositories)

  # Role names are ACCOUNT-WIDE in IAM, and the shared account hosts every
  # org — so the name carries the org id (the boundary) plus a short hash of
  # the (repository, github repo) pair, keeping under IAM's 64-char limit.
  # Readability lives in the tags.
  name                 = "addon-ecr-push-${var.organization_id}-${substr(sha256("${var.repository_name}/${each.value}"), 0, 12)}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:sub" = "repo:${each.value}:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    "ManagedBy"                               = "terraform"
    "cloud.namazustudios.com/organization_id" = var.organization_id
    "RepositoryName"                          = var.repository_name
    "GithubRepo"                              = each.value
  }
}

resource "aws_iam_role_policy" "push" {
  for_each = toset(var.github_repositories)

  name = "push-to-${local.sanitize}"
  role = aws_iam_role.push[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Auth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "PushThisRepoOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
        ]
        Resource = aws_ecr_repository.repo.arn
      }
    ]
  })
}
