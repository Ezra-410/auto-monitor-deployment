# Investigation questions — answers (all milestones)

Short, plain-language answers you can say out loud. 🟢 = "simple version" when it helps.

## Milestone 1 — application & workflow
1. **What happens when a developer pushes?** Before: nothing (only stored). Now: CI runs automatically on the branch (validate, tests, SAST, SCA, build, package); on a PR to `main` the result becomes a required check.
2. **Components that must be built first?** The 4 images: backend jar (Maven), frontend Nuxt output, ws-gateway TypeScript → JS, agent Python image. MySQL and PostgreSQL use upstream images; PostgreSQL needs `init.sql`, MySQL is migrated by Flyway when the backend starts.
3. **Dev vs production config?** All passwords/tokens/keys, admin password, LLM keys and provider (mock in dev), public URLs (localhost vs HTTPS domain). See `docs/01-architecture.md §5`.
4. **Accidentally committed DB password?** It's in Git history forever (and in every clone/fork) even after deleting the file → must be considered leaked: rotate it first, then purge history. Our Gitleaks history scan blocks delivery.
5. **Should every developer deploy to production?** No — least privilege & separation of duties: a mistake or a stolen laptop would directly hit customers. Developers merge; an approved pipeline deploys after review.
6. **What does an attacker gain from the repo?** Architecture, endpoints, internal API design, dependency versions (→ known CVEs), any committed secret (we found a real RSA test key), CI configuration (→ how to attack the pipeline).
7. **Unverified dependencies risk?** Malicious or vulnerable code runs inside our app and our CI (typosquatting, hijacked package, known CVEs). Mitigation: lockfiles, SCA, pinned SHAs/checksums, SBOM.

## Milestone 2 — CI pipeline
1. **What is a runner / where does code run?** The machine that executes jobs. Here: a fresh GitHub-hosted Ubuntu VM per job, deleted afterwards.
2. **Permissions a runner needs?** Read the repo, write reports; only specific jobs get more (`packages: write` to push, environment secrets to deploy). Declared per job.
3. **Attacker controls a runner?** Can read every secret given to jobs there, alter build output (backdoored image), push with the job token, pivot into the network. Hence ephemeral runners, minimal secrets, signing+verification.
4. **Production credentials for every job?** No. Only the production deploy job, after approval, from main (environment secrets).
5. **Developer vs external contributor pipeline?** Fork PRs run with read-only token, no secrets, and require maintainer approval to run — their code is untrusted.
6. **Can two executions interfere?** On shared/persistent runners yes (leftover files, caches, Docker state). We use ephemeral VMs + `concurrency` (CI cancels older, CDP serialises per environment).
7. **Build succeeds but tests fail?** Build job never runs here (`needs: [test, sast, sca]`) and "CI evidence" is red → cannot merge or deliver.
8. **Traceable build for a source revision?** Everything keyed by the commit SHA: artifact names, `build-info.json`, image tag `sha-<commit>`, OCI revision label, digest, signed attestation linking digest ↔ commit ↔ workflow run.

## Milestone 3 — application & dependency security
1. **Vulnerability?** A weakness that lets someone break confidentiality, integrity or availability.
2. **Our code vs third-party?** Ours: we fix it (SAST finds it). Third-party: inside a library (SCA finds it) — we upgrade, patch or mitigate; we depend on the maintainer.
3. **CVE?** Public unique ID for a known vulnerability (e.g. CVE-2021-44906), with description and CVSS severity.
4. **HIGH always exploitable?** No. Depends whether the vulnerable code is reachable, configuration, exposure. Severity ≠ risk in *our* context.
5. **Should every vulnerability block a release?** No → fatigue and bypassing. We block fixable CRITICAL (app/image) and HIGH+ (IaC); others are tracked with deadlines.
6. **False positives effect?** Wasted time, "alert fatigue", developers start ignoring or disabling the tool. Handle with documented exceptions.
7. **Vulnerability exception & who authorises?** A recorded, time-limited acceptance of a known finding with justification; approved by the security owner (CODEOWNER), not the developer who wants to ship.
8. **Why source-only scanning is insufficient?** Dependencies, the OS packages in the image, configuration (IaC), secrets and the running behaviour are not in our source. SEC-04 proved it: CI green, image scan red.
9. **Retention & review of reports?** Artifacts 90 days + Security tab; reviewed on every PR and weekly; exceptions reviewed at expiry.
10. **New CVE after deployment?** The deployed image is still vulnerable. Detect by re-scanning published images/SBOM on schedule, assess, then patch + redeploy or roll back; Dependabot opens the upgrade PR.

## Milestone 4 — IaC security
1. **IaC?** Describing infrastructure in versioned code (Terraform) instead of console clicks → repeatable, reviewable, auditable, scannable.
2. **Scan before deployment, why?** Fix is a one-line change and nothing is exposed yet; after deployment the database may already be public and breached.
3. **Config vs real infrastructure?** The file is the *desired* state; reality is what exists in AWS (+ manual changes, defaults, provider behaviour). Terraform state links them.
4. **Secure file → insecure cloud?** Yes: console changes, weak variables at apply time, provider defaults, other resources/accounts, compromised credentials, scanner blind spots.
5. **Configuration drift?** Real infrastructure diverges from the code (manual hot-fix). Detect with scheduled `terraform plan`.
6. **Separate deploy vs validate permissions?** Validation needs read-only; deploy can destroy. Our OIDC design: `tf-plan` read-only role vs `deployer` only from protected production environment.
7. **Developer modifying production infra directly?** No: changes via PR, reviewed, scanned, applied by the pipeline.
8. **Security rule removed from scanning config?** Silently lets misconfigurations through → skips are inline + reviewed by CODEOWNERS, policy guard, scanners run from a repo devs can't edit.
9. **Limits of automatic scanners?** Only known patterns; no business context; false positives/negatives (Trivy missed the `*:*` IAM policy; none flagged the hard-coded password); can't see runtime/drift.
10. **Reviewed & traceable infra changes?** PR + code-owner review + scan evidence + plan output + Git history + CloudTrail.

## Milestone 5 — containers & artifacts
1. **Image vs container?** Image = read-only template (layers). Container = running instance of it with its own process, writable layer and config.
2. **Vulnerable image with secure deps?** Base OS packages (openssl, libc…), tools added in the Dockerfile, outdated runtime.
3. **Untrusted base image risk?** Backdoors, cryptominers, outdated packages, no updates.
4. **Why not root?** If the app is compromised, root in the container makes escape and tampering much easier.
5. **Passwords in build args/layers?** Every layer is stored and downloadable; `docker history`/layer extraction reveals them, forever, to anyone who can pull.
6. **Tag vs digest?** Tag = movable name; digest = hash of content, immutable.
7. **Immutable artifact importance?** What was tested is exactly what runs; reproducible rollbacks; audit.
8. **Approved image replaced in registry?** With tags, prod could run the attacker's image. We deploy by digest + verify attestation → the replacement is not deployed.
9. **Prod builds its own images or consumes approved ones?** Consumes approved artifacts — build once, scan, sign, promote.
10. **Prove prod image = scanned image?** Same digest in the scan report, release manifest, attestation, and `docker inspect` of the running container (step "Verify running images = approved digests").

## Milestone 6 — identities, secrets, deployment
1. **Why is CI/CD privileged?** It holds secrets, can push code/images, sign releases and deploy to production.
2. **Authentication vs authorization?** Who you are (login, OIDC token) vs what you may do (permissions, environment rules).
3. **Least privilege?** Each identity gets only the permissions needed for its task, only for as long as needed.
4. **Why build jobs don't get prod credentials?** They run dependency code (npm/maven scripts) → a malicious package would steal them.
5. **Masked vs protected variables?** Masked: hidden as `***` in logs. Protected: only available to protected branches/environments. GitHub: all secrets masked; environment secrets + branch policy = protected.
6. **Secrets exposed to untrusted MR code?** The PR code can simply print/send them → GitHub gives no secrets to fork PRs; prod secrets only in env jobs on main.
7. **How OIDC reduces risk?** No stored long-lived key to steal; the cloud issues 1-hour credentials only to a token that proves repo + environment.
8. **Separate prod vs dev permissions?** Limits blast radius of mistakes and compromised dev credentials.
9. **Attacker edits pipeline to exfiltrate secrets?** On a branch: gets no env secrets (SEC-07). To reach main: review + CODEOWNERS + policy guard (SEC-08). Delivery/deploy gates in another repo.
10. **Only approved revisions reach prod?** Protected main + CI green check + CDL verifies CI for that SHA + publish only from main + CDP verifies run/attestation + approval.
11. **Protected branch vs protected environment?** Branch: who/how code changes on `main`. Environment: which jobs/branches may deploy and use its secrets, with approval.
12. **Evidence of who authorized/executed?** Actions run (actor, SHA), environment deployment history (approver, time), `deployed-<env>.json`, release manifest, attestation.

## Milestone 7 — validation
1. **All scans pass but insecure app?** Yes: logic flaws, auth bugs, unknown (0-day) vulns, misconfigured runtime, scanner blind spots.
2. **Risks not covered by Checkov/Trivy?** Business logic, runtime attacks, malicious-but-unreported packages, insider abuse, compromised CI platform, prompt injection into the agent.
3. **Compromising a trusted dependency/image?** Maintainer account takeover, tag hijack (Trivy 2026), typosquatting, malicious update, compromised build of upstream.
4. **CI/CD platform compromised?** Attacker can sign and deploy anything → keep platform-independent controls: approval, runtime monitoring, separate cloud accounts, short-lived creds, audit logs outside the platform.
5. **Detect pipeline config changes?** Git history, CODEOWNERS reviews, policy guard, required checks, audit log alerts.
6. **Malicious code through an approved dependency?** Pin exact versions/hashes, review updates (Dependabot PRs), SBOM, minimal deps, provenance (npm provenance/Sigstore), sandboxed builds.
7. **Software supply chain security?** Protecting everything that goes into the software and its path to production: code, deps, tools, build, artifacts, delivery.
8. **Signing & provenance improve?** Prove who built an artifact, from which source, with which workflow; any unsigned/tampered artifact is rejected at deploy (SLSA).
9. **Prevent vs detect?** Prevent stops it happening (gate blocks); detect notices it happened/is happening (report, alert). Need both.
10. **Mandatory now vs progressive?** Mandatory: tests, secret scan, critical vuln gate, IaC gate, protected main, env approval, least-privilege tokens. Progressive: DAST, signed commits, runtime admission control, egress control, HIGH gates.
11. **Investigate a deployed-but-vulnerable release?** From the deployment record → digest → manifest → CDL run (scan reports, SBOM) → commit → PR/reviewers; was the CVE known at scan time? exception? Then fix/rollback and improve the gate.
12. **Sensitive enterprise data?** Encryption everywhere (done in TF), DAST + pentest, data classification, DLP, WORM audit logs, SSO/MFA on the app, two-person approval, vault-based dynamic secrets, separate accounts.
