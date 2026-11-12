# namazu-cloud-addon-organization-ecr-repository

Per-organization **ECR repository** as a shared addon, in Namazu's shared
hosting AWS account (`308044622771`) — where tenant isolation does NOT come
from account boundaries, so this addon carries ownership explicitly.

One repo = one addon = one Terraform root. Inert by design: no CI, no
bootstrap — an org fork executes this root under **its** executor role at a
pinned ref. `repository_name` is deliberately default-less: **the consuming
fork's matrix entry IS the request and the config** (the runner's
`contract` input).

## What it creates (per install)

- **ECR repo** `<organization-id>/<repository-name>` (the org's database
  unique id as the prefix), `IMMUTABLE` (digest-pin workflow carries over
  1:1), scan-on-push, AES256 (not KMS — keeps the node-role IAM story
  unchanged), lifecycle: keep last 20 tagged / expire untagged after 14d.
  Tagged `ManagedBy` (+ product sku when present) for shared-account audit.
- **Per-namespace pull enforcement** (decided 2026-11-12): the repository
  policy grants pull ONLY to the installing tenant's principals — the node
  role (bound from `$instance.karpenter_node_role_name`) plus any named
  extra readers (e.g. the namespace's IRSA roles via
  `extra_reader_role_arns`).
- **CI push wiring**: one IAM role per input GitHub repository, trusted via
  GitHub OIDC **pinned to main only** (`repo:<owner>/<name>:ref:refs/heads/main`),
  permissions scoped to THIS repo's ARN. The consuming fork's bootstrap
  mints the GitHub OIDC provider (or pass `github_oidc_provider_arn`).

## Inputs

| Input | Source | Notes |
|---|---|---|
| `karpenter_node_role_name` | `$instance.karpenter_node_role_name` | the per-namespace pull principal (generic platform fact) |
| `repository_name` | fork `contract` | the tail after `<organization-id>/`; default-less |
| `github_repositories` | fork `contract` | `["owner/name", ...]` — one push role each |
| `extra_reader_role_arns` | fork `contract` | additional pull principals |
| `github_oidc_provider_arn` | fork `contract` | optional; else looked up by URL |

## Multiple repos per org (variant)

One entry per repository, each independently sweepable:

```yaml
- { addon: ".../namazu-cloud-addon-organization-ecr-repository", ref: "<pin>",
    variant: acestep-runner, instance: "<id>",
    contract: |-
      repository_name=acestep-runner
      github_repositories=["NamazuStudios/fake-the-music-server"] }
```

## What the consuming org fork needs

`iam.policy.json` (feature grants): `ecr:CreateRepository/DescribeRepositories/
DeleteRepository/PutLifecyclePolicy/GetLifecyclePolicy/SetRepositoryPolicy/
GetRepositoryPolicy/DeleteRepositoryPolicy/TagResource/ListTagsForResource`
scoped to `arn:aws:ecr:*:*:repository/<organization-id>/*`; push-role
management (`iam:CreateRole/DeleteRole/TagRole/UntagRole/PutRolePolicy/
GetRolePolicy/DeleteRolePolicy/GetRole`) scoped to
`arn:aws:iam::*:role/addon-ecr-push-*`; `iam:GetOpenIDConnectProvider` on
the GitHub OIDC provider. No Kubernetes RBAC — this addon is AWS-only.

**Sweep safety:** sweep destroys from state — deleting a repository that
still holds images requires the executor to hold `ecr:DeleteRepository`
on it (granted here, org-scoped). Before removing an entry, confirm the
repo's digests are migrated or re-pinned; deletion is unrecoverable.

## Outputs

`$addon.organization-ecr-repository.<variant>.{repository_uri, registry,
repository_arn, push_role_arns}`.

## License

MIT — see [LICENSE](LICENSE).
