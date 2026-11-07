# 09 · Security test report (Milestone 7)

Tester: Mosoh Ezra · Date: 2026-11-07 · Environment: test branches + `staging` (non-production)
Procedures: `security-tests/README.md`. Fill the **Run** and **Evidence** columns as you execute.

| Test | Scenario | Expected | Observed | Result | Run | Evidence |
|---|---|---|---|---|---|---|
| SEC-01 | Django 3.2.0 added to agent | SCA blocks | SCA gate failed on CRITICAL CVE(s); build skipped | ☐ PASS | | screenshot + `sca-report` |
| SEC-02 | RSA key hard-coded in `agent/app/dev_key.py` | Secret detected | Gitleaks private-key + Trivy AsymmetricPrivateKey | ☐ PASS | | `secret-scan-report` |
| SEC-03 | `insecure_sec03.tf` | IaC scan blocks | Checkov/Trivy/tfsec failed, PR blocked | ☐ PASS | | `iac-scan-report` |
| SEC-04 | minimist 1.2.5 installed in ws-gateway image | Image scan blocks | CVE-2021-44906 CRITICAL, not published | ☐ PASS | | `image-scan-ws-gateway` |
| SEC-05 | CDP from `test/sec-05…` | Rejected | Authorize rule 1 failed | ☐ PASS | | screenshot |
| SEC-06 | Production without approval | Blocked | Waiting → rejected, job never ran | ☐ PASS | | env history screenshot |
| SEC-07 | Probe job reads prod secrets | Denied | Job A: empty; job B: env protection refused branch | ☐ PASS | | log screenshot |
| SEC-08 | `--exit-code 0` in ci_sca | Detected / prevented | Policy guard failed + PR needs code-owner review | ☐ PASS | | PR screenshot |
| SEC-09 | Deploy release of failed CDL run | Rejected | Authorize rule 2 failed | ☐ PASS | | screenshot |
| SEC-10 | Simulated broken release | Reported + recovered | Health wait failed, diagnostics saved, rolled back | ☐ PASS | | summary screenshot |

## Positive path evidence
| Check | Run |
|---|---|
| CI green on main | |
| CDL green on main (4 images published, manifest) | |
| CDP staging green | |
| CDP production approved & green | |
| Deployed digests = manifest (step "Verify running images") | |

## False positives & approved exceptions
See `docs/SECURITY-EXCEPTIONS.md` (EXC-01 … EXC-08).

## Controls that remain incomplete (limitations)
| ID | Limitation | Risk |
|---|---|---|
| L-01 | Terraform validated & scanned but not applied (no AWS account) → OIDC deployer role not exercised; deployment targets an ephemeral runner | demo ≠ real cloud |
| L-02 | Single maintainer: approvals/reviews done by the same person (no true 4-eyes) | insider risk |
| L-03 | Frontend has no unit tests; no DAST (running-app scan) | logic bugs, runtime vulns |
| L-04 | Hosted runners have unrestricted egress | exfiltration if a tool is compromised |
| L-05 | Attestations verified at deploy, not enforced on the host at runtime (no admission control) | manual `docker run` bypass on a host |
| L-06 | Python dependencies resolved at scan time (no committed lockfile) | scan ≠ exact build if a new version appears between |
| L-07 | Test private key still in Git history (EXC-06) | key reuse |
| L-08 | No DB backup/restore test; rollback does not roll back DB migrations | data loss on bad migration |

## Recommendations (next iteration)
1. Apply Terraform to a sandbox AWS account through the OIDC roles; deploy through SSM.
2. Add a second reviewer (CODEOWNER + environment reviewer) and set `prevent_self_review` + `ENFORCE_ADMINS=true`.
3. Add DAST (OWASP ZAP baseline on staging) and frontend unit tests.
4. Commit a Python lockfile (`pip-compile`/`uv lock`), pin base images by digest (Dependabot keeps them fresh).
5. Egress allow-list for runners (e.g. Harden-Runner) + VPC endpoints in AWS.
6. Purge EXC-06 key from history, generate test keys at runtime.
7. Continuous re-scanning of published images (scheduled Trivy on the latest manifest) to catch new CVEs after release.
