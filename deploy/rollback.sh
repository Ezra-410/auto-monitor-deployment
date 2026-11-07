#!/usr/bin/env bash
# =============================================================================
# Rollback (SEC-10): redeploy the last release that was successfully deployed
# to the same environment. Uses the "deployed-<env>" record kept by every
# successful CDP run. Exits 0 only if the old release is healthy again.
# =============================================================================
set -euo pipefail
ENVIRONMENT="${1:?usage: rollback.sh <environment>}"
cd "$(dirname "$0")"

echo "Looking for the last known-good release of '${ENVIRONMENT}'..."
prev_run=""
for id in $(gh api "repos/${GITHUB_REPOSITORY}/actions/workflows/cdp_main.yml/runs?branch=main&per_page=30" \
              --jq '.workflow_runs[] | select(.id != '"${GITHUB_RUN_ID}"') | .id'); do
  if gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${id}/artifacts" --jq '.artifacts[].name' \
       | grep -qx "deployed-${ENVIRONMENT}"; then
    prev_run="$id"; break
  fi
done

if [ -z "$prev_run" ]; then
  echo "::error::No previous successful release for ${ENVIRONMENT}. Follow the manual runbook (docs/RUNBOOK-ROLLBACK.md)."
  exit 1
fi

gh run download "$prev_run" -R "$GITHUB_REPOSITORY" -n "deployed-${ENVIRONMENT}" -D previous
prev=previous/deployed-${ENVIRONMENT}.json
echo "Rolling back to the release deployed by run ${prev_run}:"
cat "$prev"

# Swap the image digests back and restore the known-good configuration.
sed -i \
  -e "s#^FRONTEND_IMAGE=.*#FRONTEND_IMAGE=$(jq -r '.images.frontend' "$prev")#" \
  -e "s#^BACKEND_IMAGE=.*#BACKEND_IMAGE=$(jq -r '.images.backend' "$prev")#" \
  -e "s#^AGENT_IMAGE=.*#AGENT_IMAGE=$(jq -r '.images.agent' "$prev")#" \
  -e "s#^WS_GATEWAY_IMAGE=.*#WS_GATEWAY_IMAGE=$(jq -r '.images["ws-gateway"]' "$prev")#" \
  .env
db_pw=$(grep '^MYSQL_PASSWORD=' .env | cut -d= -f2-)
sed -i "s#^BACKEND_DB_PASSWORD=.*#BACKEND_DB_PASSWORD=${db_pw}#" .env

docker compose --env-file .env down --remove-orphans   # keep data volumes
docker compose --env-file .env pull --quiet
docker compose --env-file .env up -d --wait --wait-timeout 420
bash smoke-test.sh

{
  echo "## ROLLED BACK (${ENVIRONMENT})"
  echo "The new release failed. Service restored to the release of CDP run ${prev_run}:"
  echo '```json'; cat "$prev"; echo '```'
} >> "$GITHUB_STEP_SUMMARY"
echo "::warning::Deployment failed and was rolled back to run ${prev_run}"
