# 05 · Security gates, thresholds & exceptions (Milestones 3–5)

## Gates

| Gate | Tool (pinned) | Scope | Blocks on | Reported only |
|---|---|---|---|---|
| Secret hygiene | shell | tracked files | `.env`, `*.pem`, `*.key`, `id_rsa` tracked | — |
| SAST | Semgrep 1.184.0 `p/default` | app source | severity ERROR | WARNING, INFO |
| SCA | Trivy 0.69.3 | lockfiles + resolved Python deps | CRITICAL **with fix available** | everything else (HIGH triaged ≤ 30 days) |
| Secrets | Gitleaks 8.24.3 + Trivy | full Git history (app + deployment) + files | **any** finding | — |
| IaC | Checkov 3.4.3 | Terraform, Dockerfiles | any failed check | — |
| IaC | Trivy config | Terraform, Dockerfiles | HIGH, CRITICAL | MEDIUM, LOW |
| IaC | tfsec 1.28.14 | Terraform | HIGH, CRITICAL | MEDIUM, LOW |
| Image | Trivy image | final image (OS + libs) | CRITICAL with fix | everything else |
| Source approval | GitHub API | delivered commit | no successful CI run | — |
| Publication | — | — | commit not on `main`, PR, non-main pipeline → image never pushed | — |
| Deployment | cdp_authorize | release | not from `main`; CDL run not successful / not main; digest without valid attestation | — |
| Production | GitHub environment | deploy job | no reviewer approval; branch ≠ main | — |

### Why CRITICAL-only for dependencies and images?
HIGH does not always mean exploitable (the vulnerable function may never be called). Blocking every HIGH on
hundreds of transitive packages would stop delivery for findings nobody can fix today, and teams start
bypassing the gate. CRITICAL + fix available = exploitable and fixable now → must block.
For **infrastructure** the bar is HIGH because a misconfiguration is ours and always fixable.

## Exception process
1. Developer opens a PR adding the exception **with reason, expiry date and ticket**.
2. Security owner (CODEOWNERS) reviews → approval = authorisation.
3. Exceptions live where developers cannot self-approve:
   * image CVEs & secrets: `auto-monitor-deployment/security/.trivyignore`, `security/.gitleaksignore`
   * IaC: inline `#checkov:skip=ID:reason`, `#trivy:ignore:ID`, `#tfsec:ignore:ID` (visible in the diff)
   * SAST: `# nosemgrep` on the exact line + justification comment
4. Every exception is listed in `SECURITY-EXCEPTIONS.md`. Expired Trivy entries (`exp:`) re-fail automatically.

## Report retention
SAST/SCA/IaC/secret/image reports and SBOM: **90 days** as workflow artifacts; test reports 30 days;
build artifacts 14 days; SARIF also kept in the GitHub Security tab. Release manifest & deployment records 90 days
(production: export to long-term storage — S3 bucket with versioning in Terraform — recommended).
