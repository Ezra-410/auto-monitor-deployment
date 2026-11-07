# 06 · Infrastructure as Code security (Milestone 4)

## Target infrastructure (terraform/)

```
Internet ──HTTPS 443──► WAF ─► ALB (public subnets, TLS 1.2/1.3, access logs → S3)
                                 │ 3000/4000 only
                                 ▼
                        EC2 app host (private subnet, no public IP, IMDSv2, encrypted EBS,
                                      SSM only - no SSH, runs approved images with compose)
                                 │ 3306 / 5432 only
                                 ▼
                 RDS MySQL 8.4 + RDS PostgreSQL 16 (data subnets, no Internet route,
                 encrypted KMS, TLS forced, Multi-AZ, backups 14 d, deletion protection,
                 password generated in Secrets Manager, IAM auth, logs exported)
Cross-cutting: KMS key (rotation on) · VPC Flow Logs · CloudWatch logs 365 d (KMS) ·
               S3 backups (KMS, versioning, TLS-only, lifecycle) · GitHub OIDC roles (no access keys)
```

| File | Content | Key security settings |
|---|---|---|
| `network.tf` | VPC, 3 subnet tiers ×2 AZ, IGW, NAT, routes, flow logs, SGs | default SG locked, no auto public IP, SG→SG references, data tier has no Internet route |
| `compute.tf` | EC2, ALB, target group, HTTPS listener, WAF, log groups | IMDSv2, no public IP, encrypted root disk, WAF managed rules, drop invalid headers |
| `database.tf` | 2 RDS instances, parameter groups, monitoring role | encryption at rest + in transit, private, managed password, backups, deletion protection |
| `storage.tf` | logs + backups buckets | public access block, versioning, KMS, TLS-only policy, lifecycle, access logging |
| `kms.tf` | customer-managed key | rotation, explicit key policy |
| `iam_oidc.tf` | GitHub OIDC provider + 2 roles | plan role read-only; deployer role only for `environment:production`, only `ssm:SendCommand` on one instance |

**Rules that must pass before any `terraform apply`:** `terraform fmt`, `terraform validate`, Checkov 0 failed,
Trivy 0 HIGH/CRITICAL, tfsec 0 HIGH/CRITICAL, PR reviewed by code owner, `terraform plan` reviewed (with real account).

## Tool comparison on the deliberately insecure file (SEC-03, `security-tests/sec03/insecure_sec03.tf`)

Measured locally with the same versions as the pipeline:

| Insecure item | Checkov | Trivy config | tfsec |
|---|---|---|---|
| SG: SSH 22 open to 0.0.0.0/0 | ✅ CKV_AWS_24 | ✅ AWS-0107 (HIGH) | ✅ CRITICAL |
| SG: MySQL 3306 open to 0.0.0.0/0 | ⚠️ only via public-DB checks | ❌ | ✅ CRITICAL |
| RDS publicly accessible | ✅ CKV_AWS_17 | ✅ AWS-0180 (HIGH) | ✅ CRITICAL |
| RDS not encrypted | ✅ CKV_AWS_16 | ✅ AWS-0080 (HIGH) | ✅ HIGH |
| RDS no backups / no deletion protection / no IAM auth | ✅ | ✅ (MEDIUM) | ✅ (MEDIUM) |
| S3 public-read ACL, no public access block | ✅ | ✅ (HIGH ×5) | ✅ (HIGH ×5) |
| S3 no encryption / versioning / logging | ✅ | ✅ | ✅ |
| IAM policy `Action "*" Resource "*"` | ✅ 9 checks (CKV_AWS_62, 63, 286–290, 355, CKV2_AWS_40) | ❌ **missed** | ✅ HIGH |
| Hard-coded DB password in Terraform | ❌ | ❌ | ❌ (secret scanners' job) |
| **Total findings** | **28 failed checks** | **16 (9 HIGH)** | **21 (3 CRITICAL, 12 HIGH)** |

**Conclusions**
* No single tool is enough: Trivy missed the admin IAM policy, Checkov didn't flag the open MySQL port as such, none flagged the hard-coded password → use several tools + secret scanning + human review.
* Checkov understands relationships between resources (graph): fewer false positives with `for_each`/references. tfsec/Trivy are faster and had false positives on `for_each` (fixed by rewriting the code).
* tfsec is now maintained as part of Trivy → long term, keep Checkov + Trivy, tfsec as optional second opinion.
* Severity scales differ between tools (Checkov has none by default) → the policy is defined per tool.
