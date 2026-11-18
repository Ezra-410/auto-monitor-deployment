# 09 · Security test report (Milestone 7)

Tester: Mosoh Ezra · Dates: 2026-11-07 → 2026-11-17 · Environment: test branches + `staging` (non-production)
Procedures: `security-tests/README.md`.
Run links: app repo = `https://github.com/Ezra-410/auto-monitor/actions/runs/<ID>`, deployment repo = `https://github.com/Ezra-410/auto-monitor-deployment/actions/runs/<ID>`.

## Results

| Test | Scenario | Expected | Observed | Result | Run |
|---|---|---|---|---|---|
| SEC-01 | Django 3.2.0 added to `agent/requirements.txt` | SCA blocks | SCA gate failed on CRITICAL CVEs; Build & Package skipped. Revert → green | ☑ PASS | app 42341881546 |
| SEC-02 | RSA private key hard-coded in `agent/app/dev_key.py` | Secret detected | Caught **earlier than planned**: Semgrep (CI SAST) failed on the private key; Gitleaks also found it; CDL refused delivery (no green CI) | ☑ PASS | app 42355789355 · deploy 42356372557 |
| SEC-03 | `insecure_sec03.tf` (public DB, open SSH/MySQL, public S3, `*:*` IAM) | IaC scan blocks | Checkov, Trivy and tfsec failed; "CDL gate" red; PR blocked | ☑ PASS | deploy 42350169079 |
| SEC-04 | `minimist@1.2.5` installed inside the ws-gateway image | Image scan blocks | CI green (lockfile SCA cannot see it); `Image · ws-gateway` failed (CVE-2021-44906), other 3 images passed; release manifest skipped, nothing published | ☑ PASS | deploy 42356381643 |
| SEC-05 | CDP started from `test/sec-05-unauthorized-deploy` | Rejected | Authorize rule 1 rejected (ref is not `refs/heads/main`) | ☑ PASS | deploy 42355860831 |
| SEC-06 | Production deployment, reviewer rejects | Blocked | Staging deployed; production waited for review; rejected; production job never ran | ☑ PASS | deploy 44206181654 |
| SEC-07 | Probe workflow reads production secrets | Denied | Job A (no environment): `JWT_PRIVATE_KEY length = 0`, "ACCESS DENIED (expected)". Job B (`environment: production` from a test branch): refused by environment protection, never started | ☑ PASS | deploy 42355855485 |
| SEC-08 | `--exit-code 0` in `ci_sca.yml` (PR) | Detected / prevented | Policy guard failed; PR blocked (required check + code-owner review) | ☑ PASS | app 42355847521 |
| SEC-09 | CDP with the run ID of the failed SEC-04 CDL run | Rejected | Authorize rule 2 rejected: that release never succeeded, so no approved manifest/attestation | ☑ PASS | deploy 42355913192 |
| SEC-10 | `simulate_failure=true` (wrong DB password) | Reported + recovered | "Start the stack" failed (backend unhealthy); diagnostics saved; "Roll back to the last known-good release" succeeded; summary "ROLLED BACK (staging)" | ☑ PASS | deploy 42355916869 |

## Milestone 2 pipeline tests

| Test | Expected | Observed |
|---|---|---|
| Valid change (`feature/readme-note`) | green | success |
| Deliberate failing test (`test/m2-failing-test`) | Test red, Build skipped | failure |
| Invalid build configuration (`test/m2-invalid-build`, `FRM` in Dockerfile) | Package red | failure |

## Positive path evidence

| Check | Run |
|---|---|
| CI green on main (after CVE fix) | app 42348975479 |
| CDL green on main: 4 images published, signed, release manifest | deploy 42349403670 |
| CDP staging + production **approved** and deployed | deploy 42350301743 (also 42355865734) |
| Deployed digests = manifest ("Verify running images = approved digests") | deploy 42350301743 |
| Branch protection on `main` (required checks "CI evidence" / "CDL gate", PR + code-owner review) | `scripts/protect-branches.sh`, verified 2026-11-17 |

## Real findings discovered by the pipeline (not planned tests)

| # | Finding | Detected by | Outcome |
|---|---|---|---|
| F-1 | Hard-coded Keycloak DB password in `iam/docker-compose.yml` (commit 0c6d5b5, branch `module2-sso` of the same repo) | Gitleaks history scan — first CDL run blocked (deploy 42344690385) | Secret scan scoped to the delivered commit's history (`--log-opts="--full-history HEAD"`). **Action: rotate the Keycloak password, move it to `.env`.** |
| F-2 | 11 CRITICAL CVEs in the backend image (Spring Boot 3.4.4 → Tomcat 10.1.39, Spring Security 6.4.4, spring-webmvc 6.2.5). CI SCA missed them (versions come from the Spring Boot parent) | Trivy image scan (deploy 42345386424) | Fixed in PR #1: Spring Boot 3.5.11, Tomcat 10.1.61, Spring Security 6.5.9 (CI green, CDL green) |
| F-3 | 2 spring-webmvc CVEs fixed only in Spring Framework 7 (Spring Boot 4) | Trivy image scan | Time-limited exception EXC-09 (expires 2026-12-31) |
| F-4 | Real RSA private key in `JwtServiceTest.java` (test fixture) | Gitleaks | Approved exception EXC-06 |
| F-5 | Start-up deadlock (backend readiness needs agent; agent waited for healthy backend) | Analysis of compose file | Fixed: agent depends on `backend: service_started` |

## False positives & approved exceptions
See `docs/SECURITY-EXCEPTIONS.md` (EXC-01 … EXC-09).

## Controls that remain incomplete (limitations)
| ID | Limitation | Risk |
|---|---|---|
| L-01 | Terraform validated & scanned but not applied (no AWS account) → OIDC deployer role not exercised; deployment targets an ephemeral runner | demo ≠ real cloud |
| L-02 | Single maintainer: approvals/reviews done by the same person (no true 4-eyes) | insider risk |
| L-03 | Frontend has no unit tests; no DAST (running-app scan) | logic bugs, runtime vulns |
| L-04 | Hosted runners have unrestricted egress | exfiltration if a tool is compromised |
| L-05 | Attestations verified at deploy, not enforced on the host at runtime (no admission control) | manual `docker run` bypass on a host |
| L-06 | Python dependencies resolved at scan time (no committed lockfile) | scan ≠ exact build if a new version appears between |
| L-07 | Test private key still in Git history (EXC-06); Keycloak password (F-1) still in history of `module2-sso` | key reuse |
| L-08 | No DB backup/restore test; rollback does not roll back DB migrations | data loss on bad migration |

## Recommendations (next iteration)
1. Apply Terraform to a sandbox AWS account through the OIDC roles; deploy through SSM.
2. Add a second reviewer (CODEOWNER + environment reviewer) and set `prevent_self_review` + `ENFORCE_ADMINS=true`.
3. Add DAST (OWASP ZAP baseline on staging) and frontend unit tests.
4. Commit a Python lockfile, pin base images by digest (Dependabot keeps them fresh).
5. Egress allow-list for runners + VPC endpoints in AWS.
6. Purge EXC-06 key from history; rotate the Keycloak password (F-1); migrate to Spring Boot 4 before EXC-09 expires.
7. Scheduled re-scans of released images to catch new CVEs after release.
