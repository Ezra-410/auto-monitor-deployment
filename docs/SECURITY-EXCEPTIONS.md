# Approved security exceptions & false positives

| ID | Where | Tool / rule | Type | Reason | Approved by | Review date |
|---|---|---|---|---|---|---|
| EXC-01 | `terraform/network.tf` ALB SG ingress 443 0.0.0.0/0; `compute.tf` public ALB | Trivy AVD-AWS-0107/0053, tfsec | Accepted by design | A public web app must accept HTTPS from the Internet. Only the ALB is public, protected by WAF (Common, KnownBadInputs, AnonymousIp) | @Ezra-410 | 2027-05-07 |
| EXC-02 | `network.tf` app SG egress 443 0.0.0.0/0 | Trivy AVD-AWS-0104, tfsec | Accepted risk | Host must pull images / call LLM APIs / SSM. Next iteration: VPC endpoints + egress allow-list proxy | @Ezra-410 | 2027-02-07 |
| EXC-03 | `storage.tf` logs bucket SSE-S3 not KMS | Checkov CKV_AWS_145, Trivy AVD-AWS-0132, tfsec | Technical constraint | ALB access logs cannot be written to a KMS-encrypted bucket | @Ezra-410 | 2027-05-07 |
| EXC-04 | `storage.tf` logs bucket without access logging | Checkov CKV_AWS_18, Trivy, tfsec | Technical constraint | It *is* the log bucket (logging into itself loops) | @Ezra-410 | 2027-05-07 |
| EXC-05 | `agent/app/db.py` `update_job` f-string SQL | Semgrep sqlalchemy-execute-raw-query | **False positive** | Column names come only from a hard-coded allow-list; values are bound parameters | @Ezra-410 | — |
| EXC-06 | `backend/src/test/.../JwtServiceTest.java` (commit 2a565ce) | Gitleaks private-key | Accepted risk (temporary) | RSA key is a unit-test fixture, never used in any environment. Action: generate key at test runtime, then purge from history (git filter-repo) | @Ezra-410 | 2026-12-07 |
| EXC-07 | `kms.tf` key policy `Resource "*"` | Checkov CKV_AWS_111/356/109 | False positive | In a KMS key policy `*` means "this key" | @Ezra-410 | — |
| EXC-08 | S3 cross-region replication / event notifications | Checkov CKV_AWS_144, CKV2_AWS_62 | Deferred | Single-region lab; added in next iteration | @Ezra-410 | 2027-02-07 |

### Tool-comparison false positives fixed in code (not excepted)
* tfsec and Trivy did not understand `for_each` over bucket objects and reported 12 false "no public access block / no versioning" findings; Checkov (graph-based) did not. The S3 resources were rewritten one-per-bucket so all three tools agree.
