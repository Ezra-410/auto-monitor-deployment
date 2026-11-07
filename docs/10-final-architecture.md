# 10 · Final secure CI/CD architecture (Final Architecture Challenge)

```mermaid
flowchart LR
  dev(["Developer"]) -->|"push branch / PR"| app[(auto-monitor repo<br/>main protected<br/>CODEOWNERS)]
  subgraph CI["CI · auto-monitor (ci_main.yml) — GitHub-hosted ephemeral runners, token read-only"]
    v["1 Validate<br/>hygiene · actionlint · policy guard · ruff"] --> t["2 Test<br/>JUnit · pytest · vitest · typecheck"]
    v --> s["3a SAST<br/>Semgrep"]
    v --> c["3b SCA<br/>Trivy + SBOM"]
    t & s & c --> b["4 Build"] --> p["5 Package<br/>docker build, no push"]
  end
  app --> CI
  CI -->|"CI evidence check"| app
  subgraph CDL["CDL · auto-monitor-deployment (cdl_main.yml)"]
    vs["1 Verify source<br/>CI green for SHA? on main?"] --> sc["2a Secrets<br/>Gitleaks full history + Trivy"]
    vs --> mc["2b IaC<br/>Checkov · Trivy · tfsec · tf validate"]
    sc & mc --> bsp["3 Build → Trivy image gate → push by digest → sign attestation"]
    bsp --> man[["release-manifest.json<br/>image@sha256 ×4"]]
  end
  app -.->|"read-only PAT"| vs
  bsp -->|"GITHUB_TOKEN packages:write<br/>OIDC → Sigstore"| reg[(GHCR<br/>images + attestations)]
  subgraph CDP["CDP · cdp_main.yml (manual)"]
    au["1 Authorize<br/>from main? CDL run ok? attestation valid?"] --> st["2 Deploy staging<br/>env secrets: staging"]
    st --> ap{"Required reviewer<br/>approval"}
    ap -->|"approved"| pr["3 Deploy production<br/>env secrets: production"]
  end
  man --> au
  reg -->|"pull by digest"| st & pr
  pr --> env[(Deployment target<br/>runner VM / AWS EC2 via SSM + OIDC)]
  pr --> audit[["Audit trail: run history · environment approvals · deployed-env.json"]]
```

## How each requirement is met
| # | Question | Answer |
|---|---|---|
| 1 | How developers submit changes | Branch → PR to `main`; protected branch needs green "CI evidence", 1 approval, code-owner review |
| 2 | How the CI/CD platform executes jobs | GitHub Actions on ephemeral GitHub-hosted VMs, one per job; reusable workflows per stage |
| 3 | Tests & scans | CI: tests, Semgrep (SAST), Trivy (SCA + SBOM); CDL: Gitleaks/Trivy secrets |
| 4 | Terraform validation | CDL 2b: fmt, validate, Checkov, Trivy config, tfsec — before any apply |
| 5 | Images built & scanned | CDL 3: built from verified SHA, Trivy image gate, then pushed |
| 6 | Approved artifacts stored | GHCR, immutable digest, signed provenance attestation, release manifest |
| 7 | Pipeline identities' permissions | Per-job `GITHUB_TOKEN` scopes; read-only PAT; OIDC → short-lived AWS roles (plan read-only / deployer prod-only) |
| 8 | Secrets protection | Environment secrets (masked, env-scoped), generated randomly, never in code, `.env` mode 600 on runner |
| 9 | Production authorization | `main` only + CDL success + valid attestation + required reviewer on `production` |
| 10 | Trace & investigate | commit → CI run → CDL run → digest/attestation → CDP run → approver → deployed record |

## Design review
**Preventive:** branch protection, CODEOWNERS, all gates (SAST/SCA/secrets/IaC/image), publication rules, authorize rules, environment protection & approval, least-privilege tokens, env-scoped secrets, SHA-pinned actions, non-root/cap-drop containers, WAF/SG/private subnets.
**Detective:** scan reports, policy guard, SARIF in Security tab, Dependabot, audit trail, VPC Flow Logs, CloudWatch/WAF logs, smoke tests.
**Corrective:** automatic rollback, runbook, credential rotation script, Dependabot PRs, exceptions with expiry.

**Highest risks:** the CI/CD platform itself (holds signing ability and prod secrets), the PAT, the production environment reviewer account (phishing), third-party actions/tools (supply chain), the registry.

**CI/CD platform unavailable:** nothing can be delivered → production keeps running the last release; emergency = documented manual deploy of an already-approved digest with two people, logged.

**Registry compromised:** attacker can push new images/tags but cannot forge our attestation nor change a digest's content → `gh attestation verify` + pull-by-digest refuse them. Response: rotate access, re-verify every deployed digest, rebuild from source.

**Revoke a compromised deployment credential:** environment secret → rerun `setup-github.sh` (new values) and redeploy; PAT → revoke in GitHub settings, create new one; AWS → nothing long-lived to revoke (OIDC), tighten the role trust policy if needed; review audit logs.

**Roll back a vulnerable release:** run CDP with the previous good `cdl_run_id` (approval required) — redeploys the old digests; then fix forward.

**Financial application:** two-person approval (prevent self-review), signed commits, mandatory DAST + pentest, WORM log storage, HSM/KMS-backed signing, change-advisory evidence, PCI-DSS/SOC 2 controls, runtime admission control (only signed images run), secrets in a vault with dynamic credentials, separate AWS accounts per environment.

**50 teams:** shared reusable workflows in a central "platform" repo (versioned, called by SHA), org-level rulesets instead of per-repo protection, org-wide required workflows, central exception register, self-service environments, scanner results aggregated (e.g. DefectDojo), dedicated runner groups per trust level.
