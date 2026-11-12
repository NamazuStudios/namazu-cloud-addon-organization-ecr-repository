# Addon-owned inputs. `karpenter_node_role_name` is bound from the tenant
# baseline in manifest.yaml ($instance.karpenter_node_role_name — a generic
# platform fact that exists regardless of this addon). Everything else is
# tenant-specific and rides the consuming fork's matrix entry via the
# runner's `contract` input. Contract variables (instance_id,
# organization_id, ...) are NOT declared here: see 20-variables.tf and
# author rule 1 in feature.tf.

variable "repository_name" {
  description = "The tail of the repo name: the full name is <organization-id>/<repository-name> (the org's database unique id as the ECR namespacing prefix). DELIBERATELY default-less: no contract value, no valid plan."
  type        = string
}

variable "karpenter_node_role_name" {
  description = "The tenant cluster's Karpenter node IAM role — the per-namespace pull principal (the addon's repository policy grants pull to it). Bound from the tenant baseline: $instance.karpenter_node_role_name."
  type        = string
}

variable "github_repositories" {
  description = "Zero or more GitHub repositories ('owner/name') that get their own OIDC-trusted push role (trust pinned to main only) scoped to THIS repository's ARN — the CI push wiring."
  type        = list(string)
  default     = []
}

variable "extra_reader_role_arns" {
  description = "Additional reader principals (e.g. the tenant namespace's IRSA roles) granted pull by the repository policy, beyond the node role."
  type        = list(string)
  default     = []
}

variable "github_oidc_provider_arn" {
  description = "The GitHub OIDC provider ARN to trust for push roles; empty = look it up by URL (the consuming fork's bootstrap mints it)."
  type        = string
  default     = ""
}
