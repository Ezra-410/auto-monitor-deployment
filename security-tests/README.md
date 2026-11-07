# Security test scenarios SEC-01 … SEC-10 (Milestone 7)

Conventions
* `APP` = your clone of `auto-monitor`, `DEP` = your clone of `auto-monitor-deployment`.
* Every test happens on a **`test/sec-xx-…` branch** — never on `main`. Delete the branch afterwards.
* For each test keep: the run URL + a screenshot of the red step + the downloaded report → `docs/09-security-test-report.md`.
* `gh run watch` follows the latest run in the terminal; `gh run view --web` opens it.

---

## SEC-01 · Vulnerable dependency → SCA blocks (CI, auto-monitor)
```bash
cd APP && git switch main && git pull
git switch -c test/sec-01-vulnerable-dependency
echo "Django==3.2.0" >> agent/requirements.txt      # Django 3.2.0 has CRITICAL CVEs (e.g. SQL injection CVE-2021-35042)
git commit -am "test(SEC-01): add vulnerable dependency"
git push -u origin test/sec-01-vulnerable-dependency
gh run watch
```
**Expected:** `3b · SCA / Trivy dependency scan + SBOM` ❌ at "Security gate - fail on fixable CRITICAL"; Build & Package **skipped**; "CI evidence" ❌.
**Remediation evidence:** `git revert --no-edit HEAD && git push` → SCA ✅. Compare the two `sca-report` artifacts.

## SEC-02 · Hard-coded secret → secret detection (CDL)
```bash
cd APP && git switch main && git switch -c test/sec-02-hardcoded-secret
openssl genrsa 2048 2>/dev/null | python3 -c "import sys; print('DEV_JWT_KEY = \"\"\"' + sys.stdin.read() + '\"\"\"')" > agent/app/dev_key.py
git add agent/app/dev_key.py && git commit -m "test(SEC-02): hardcoded private key"
git push -u origin test/sec-02-hardcoded-secret
gh run watch                                   # CI passes: SAST/SCA do not look for secrets
cd DEP && gh workflow run cdl_main.yml -f source_ref=test/sec-02-hardcoded-secret
gh run watch
```
**Expected:** `2a · Secret check` ❌ — Gitleaks `private-key` in `agent/app/dev_key.py` (value redacted) + Trivy `AsymmetricPrivateKey`. Nothing is built.
**Lesson:** the key is now in Git history of that branch → treat as compromised: delete branch, rotate.

## SEC-03 · Insecure Terraform → IaC scanning (CDL, PR on deployment repo)
```bash
cd DEP && git switch main && git pull && git switch -c test/sec-03-insecure-iac
cp security-tests/sec03/insecure_sec03.tf terraform/
git add terraform/insecure_sec03.tf && git commit -m "test(SEC-03): insecure terraform"
git push -u origin test/sec-03-insecure-iac
gh pr create --base main --title "SEC-03 insecure IaC (do not merge)" --body "Security test"
gh run watch
```
**Expected:** `2b · Misconfiguration check / Checkov + Trivy + tfsec` ❌ (Checkov 28 failed, Trivy 9 HIGH, tfsec 3 CRITICAL), "CDL gate" ❌ → PR shows **Merging is blocked**. Close the PR afterwards (`gh pr close --delete-branch`).

## SEC-04 · Image with a known vulnerable package → image scan blocks (CDL)
```bash
cd APP && git switch main && git switch -c test/sec-04-vulnerable-image
# install a vulnerable package INSIDE the image only (not in any lockfile)
sed -i 's#^RUN apk upgrade --no-cache$#RUN apk upgrade --no-cache \&\& npm install -g minimist@1.2.5#' ws-gateway/Dockerfile
grep -n minimist ws-gateway/Dockerfile          # check the line changed
git commit -am "test(SEC-04): vulnerable package in image"
git push -u origin test/sec-04-vulnerable-image
gh run watch                                    # CI is GREEN: lockfile SCA cannot see it
cd DEP && gh workflow run cdl_main.yml -f source_ref=test/sec-04-vulnerable-image
gh run watch
```
**Expected:** `Image · ws-gateway` ❌ at "Security gate" — `minimist` CVE-2021-44906 (CRITICAL). The 3 other images pass. Nothing published.
**Lesson:** image scanning catches what source/lockfile scanning cannot.

## SEC-05 · Deployment from an unauthorized branch → rejected (CDP)
```bash
cd DEP && git switch main && git switch -c test/sec-05-unauthorized-deploy && git push -u origin test/sec-05-unauthorized-deploy
gh workflow run cdp_main.yml --ref test/sec-05-unauthorized-deploy -f cdl_run_id=<GOOD_CDL_RUN_ID> -f target=staging
gh run watch
```
**Expected:** `1 · Authorize release` ❌ "REJECTED - deployment requested from refs/heads/test/sec-05…". (Second layer: environments accept `main` only.)

## SEC-06 · Production without approval → blocked
```bash
gh workflow run cdp_main.yml --ref main -f cdl_run_id=<GOOD_CDL_RUN_ID> -f target=production
```
Staging deploys, then `3 · Deploy production` shows **"Waiting for review"**. Click **Review deployments → Reject**.
**Expected:** production job never starts; environment history shows rejected by you.

## SEC-07 · Access production secrets from an unauthorized job → denied
```bash
cd DEP && git switch main && git switch -c test/sec-07-secret-probe
cp security-tests/sec07/sec07_secret_probe.yml .github/workflows/
git add .github/workflows/sec07_secret_probe.yml && git commit -m "test(SEC-07): secret probe"
git push -u origin test/sec-07-secret-probe
gh run watch
```
**Expected:** job A ✅ prints `length = 0` + "ACCESS DENIED (expected)"; job B ❌ "Branch test/sec-07-secret-probe is not allowed to deploy to production due to environment protection rules".

## SEC-08 · Weaken the pipeline → detected / prevented
```bash
cd APP && git switch main && git switch -c test/sec-08-weaken-pipeline
sed -i 's/--exit-code 1 \./--exit-code 0 ./' .github/workflows/ci_sca.yml
git commit -am "test(SEC-08): make SCA never fail"
git push -u origin test/sec-08-weaken-pipeline
gh pr create --base main --title "SEC-08 weaken SCA (do not merge)" --body "Security test"
```
**Expected:** `1 · Validate / Workflow lint + policy guard` ❌ "Security gate weakened"; PR blocked: required check failed + **code-owner review required** (CODEOWNERS on `.github/`). Even if merged, CDL image scan in the other repo still blocks.

## SEC-09 · Deploy an unapproved image → rejected
Use the run ID of the **failed SEC-04 CDL run** (or of the SEC-03 PR run):
```bash
gh workflow run cdp_main.yml --ref main -f cdl_run_id=<SEC04_CDL_RUN_ID> -f target=staging
```
**Expected:** `1 · Authorize` ❌ "CDL run … did not succeed: its images were never approved". (A digest without attestation fails `gh attestation verify` the same way.)

## SEC-10 · Failed deployment → reported + recovered
Requires one earlier successful staging deployment.
```bash
gh workflow run cdp_main.yml --ref main -f cdl_run_id=<GOOD_CDL_RUN_ID> -f target=staging -f simulate_failure=true
```
**Expected:** "Start the stack" ❌ (backend unhealthy: wrong DB password), `diagnostics-staging` artifact, "Roll back" step ✅ → summary "ROLLED BACK (staging)". Recovery procedure: `docs/RUNBOOK-ROLLBACK.md`.

---
Clean-up: `git push origin --delete test/sec-0X-…` for every test branch once evidence is captured.
