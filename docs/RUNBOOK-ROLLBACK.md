# Runbook — failed deployment & rollback

## Automatic (already in cdp_deploy.yml)
1. `up --wait` or smoke test fails → job marked failed.
2. Diagnostics (`ps`, last 200 log lines) saved as artifact `diagnostics-<env>`.
3. `deploy/rollback.sh` finds the last run that has a `deployed-<env>` record, redeploys those digests with the known-good config, reruns the smoke test, writes "ROLLED BACK" in the run summary.

## Manual (if automatic rollback fails or no previous release exists)
1. Actions → CDP · main → find the last green production run → note its `cdl_run_id` (in summary).
2. Run CDP again with that `cdl_run_id`, target `production` → approve → old release redeployed **by digest**.
3. Vulnerable release found later: open incident, add CVE to tracker, deploy previous release (step 2) or a fixed build; never edit images in the registry.
4. Compromised credential: rerun `scripts/setup-github.sh` (new random values) → redeploy; revoke PAT in GitHub settings; check Actions logs for its use.
5. Write the post-mortem: what failed, detection time, recovery time, fix.
