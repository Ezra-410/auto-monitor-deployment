# 04 · Pipeline design, runners & permissions (Milestone 2)

## Three separated pipelines

| Pipeline | Repo | Files | Trigger | Produces |
|---|---|---|---|---|
| **CI** – integration | `auto-monitor` | `ci_main.yml` → `ci_validate`, `ci_test`, `ci_sast`, `ci_sca`, `ci_build` | push on `main`/`develop`/`feature/**`/`fix/**`/`test/**`, PR to `main`/`develop`, manual | test reports, SAST/SCA reports, SBOM, build artifacts, "CI evidence" check |
| **CDL** – delivery | `auto-monitor-deployment` | `cdl_main.yml` → `cdl_verify_source`, `cdl_secret_check`, `cdl_misconfig_check`, `cdl_build_scan_publish` | manual (choose commit), push/PR on deployment repo `main` | scanned + signed images in GHCR, `release-manifest.json` |
| **CDP** – deployment | `auto-monitor-deployment` | `cdp_main.yml` → `cdp_authorize`, `cdp_deploy` | manual only (`cdl_run_id`, target) | running stack, `deployed-<env>.json`, GitHub Deployment record |

## CI stages (the 4 required stages + security)

| Stage | Job(s) | Fails when |
|---|---|---|
| 1 Validate | repo hygiene, compose config, actionlint, **policy guard**, ruff | `.env`/key tracked, invalid compose/workflow, security gate weakened, lint error |
| 2 Test | backend `mvn verify`, agent `pytest`, ws-gateway `vitest`, frontend `typecheck` | any test fails |
| 3a SAST | Semgrep | ERROR-severity finding |
| 3b SCA | Trivy fs + SBOM | fixable CRITICAL CVE |
| 4 Build | compile each component, `build-info.json` + `SHA256SUMS` | compile error |
| 5 Package | `docker build` of each image (no push) | Dockerfile invalid |

`needs:` makes it fail-closed: Build runs only if Test **and** SAST **and** SCA succeeded.

## Runners (where the code actually runs)
* **GitHub-hosted runners** (`ubuntu-24.04`): a brand-new VM per job, destroyed afterwards → no persistence between jobs, no cross-job contamination.
* Optional **self-hosted runner** for deployment only (`vars.DEPLOY_RUNNER=self-hosted`). Never used for CI/PR code.

## Permissions given to jobs (least privilege)

| Job | `GITHUB_TOKEN` permissions | Other credentials |
|---|---|---|
| all CI jobs | `contents: read` | none |
| SAST | + `security-events: write` (upload SARIF) | none |
| CDL verify / secret / misconfig | `contents: read` | `AUTO_MONITOR_PAT` (read-only on auto-monitor) |
| CDL build/scan/publish | `contents: read`, `packages: write`, `id-token: write`, `attestations: write` | PAT (read) |
| CDP authorize | `contents: read`, `actions: read`, `packages: read`, `attestations: read` | none |
| CDP deploy | `contents: read`, `actions: read`, `packages: read` | **environment secrets** of its environment only |

Repo setting: default workflow token = **read-only**, workflows cannot approve PRs (`scripts/setup-github.sh`).
`persist-credentials: false` on every checkout → the token is not left in `.git/config` for later steps.

## Traceability of a build
Commit SHA → CI run ID → artifact names contain the SHA → `build-info.json` → image tag `sha-<commit>` +
OCI label `org.opencontainers.image.revision` → image **digest** → signed attestation → release manifest → deployment record.

## Interference between runs
`concurrency` groups: CI cancels older runs of the same branch; CDL/CDP never cancel (no half-published release / half deployment) and CDP serialises per environment.
