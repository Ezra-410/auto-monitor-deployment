# 07 · Container build & artifact security (Milestone 5)

## Dockerfile hardening (auto-monitor/*/Dockerfile)

| Control | How |
|---|---|
| Minimal, trusted base | Official images only: `node:22-alpine`, `eclipse-temurin:21-jre-alpine` (JRE, not JDK), `python:3.12-slim` |
| Multi-stage | compilers, Maven, devDependencies stay in the build stage; runtime gets only the output |
| Pinned versions | major tags pinned; **digest pinning** (`FROM node:22-alpine@sha256:…`) recommended, kept fresh by Dependabot |
| OS patches | `apk upgrade --no-cache` / `apt-get upgrade` at build time |
| Non-root | `USER node` / `USER app` (uid 1000) — app code owned by root, so the process cannot modify itself |
| No secrets in image | secrets only at runtime via env; `.dockerignore` excludes `.env`, `*.pem`, `*.key`, `.git` |
| Health checks | `HEALTHCHECK` in every image |
| Metadata | OCI labels: title, source, **revision = commit SHA**, created |
| Runtime (compose) | `cap_drop: ALL`, `no-new-privileges`, ports bound to 127.0.0.1, images by digest |

## Publication flow (cdl_build_scan_publish.yml)
1. `docker build` from the **verified commit** (never a branch name).
2. `trivy image` full report (JSON + table) kept 90 days.
3. Gate: fixable CRITICAL → job fails, **nothing pushed**.
4. Only if commit on `main` and pipeline on `main`: `docker push ghcr.io/<owner>/auto-monitor-<c>:sha-<commit>`.
5. Read the **digest** (`sha256:…`, hash of the content).
6. `actions/attest-build-provenance`: signed (Sigstore, OIDC identity of the workflow) statement "digest X built by workflow Y from commit Z", stored in GitHub + pushed to the registry.
7. `release-manifest.json` lists `image@digest` for the 4 images → only input accepted by CDP.

## Tag vs digest
* Tag `sha-abc` = a label, can be moved to another image (even `sha-*` tags; GHCR has no tag immutability).
* Digest `sha256:…` = fingerprint of the content: change one byte → different digest. Deployment pulls **by digest**, so a replaced image in the registry is simply not the one deployed, and `gh attestation verify` proves the digest came from our pipeline.

## Retention
GHCR: keep all images referenced by a manifest of the last 90 days + the last 10 production releases;
delete untagged/unreferenced versions monthly (GHCR package settings or `actions/delete-package-versions`).
Scan reports and manifests: 90 days in Actions.
