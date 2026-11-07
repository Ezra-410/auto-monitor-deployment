# auto-monitor-deployment

Delivery (**CDL**) and deployment (**CDP**) pipelines, infrastructure (**Terraform**) and security
policy for [auto-monitor](https://github.com/Ezra-410/auto-monitor). Separated from the application
repository so application developers cannot weaken delivery and deployment controls.

| Folder | Content |
|---|---|
| `.github/workflows/cdl_*.yml` | Delivery: verify source → secret check → misconfig check → build, scan, publish, sign |
| `.github/workflows/cdp_*.yml` | Deployment: authorize → staging → (approval) → production, rollback |
| `terraform/` | AWS infrastructure (VPC, ALB+WAF, EC2, RDS, S3, KMS, OIDC roles) |
| `deploy/` | Deployment compose file (images by digest), smoke test, rollback |
| `security/` | Approved exceptions (`.gitleaksignore`, `.trivyignore`) — security-owned |
| `security-tests/` | SEC-01…SEC-10 procedures + test files |
| `scripts/` | GitHub environments/secrets setup, branch protection |
| `docs/` | Design, policy, comparison, security model, test report, final architecture, Q&A |
