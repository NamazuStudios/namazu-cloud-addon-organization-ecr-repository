# What other addons, charts, and CI can wire against. Resolves per install:
# $addon.organization-ecr-repository.<variant>.<output>

output "repository_uri" {
  description = "Full repo URI (<account>.dkr.ecr.<region>.amazonaws.com/<organization-id>/<repository-name>)."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${local.repository_name}"
}

output "registry" {
  description = "The account's registry endpoint (charts' image: prefix)."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "repository_arn" {
  description = "The repository's ARN."
  value       = aws_ecr_repository.repo.arn
}

output "push_role_arns" {
  description = "Assumable CI push roles, keyed by the input GitHub repository (trust: main only)."
  value       = { for repo, role in aws_iam_role.push : repo => role.arn }
}
