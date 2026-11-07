#!/usr/bin/env bash
# =============================================================================
# One-time GitHub configuration of the delivery system ("governance as code").
# Run from your laptop AFTER both repos are pushed:   bash scripts/setup-github.sh
# Requires: gh (logged in: gh auth login), openssl
#
# What it does
#   1. Actions hardening on both repos (read-only default token, no PR approval
#      by bots, fork PRs need approval)
#   2. Repository variables of auto-monitor-deployment
#   3. Environments "staging" and "production"
#        staging    : deployable from main only
#        production : deployable from main only + REQUIRED REVIEWER (you)
#   4. Environment secrets, generated randomly, DIFFERENT per environment.
#      Values are piped to gh through stdin: never printed, never in history.
# =============================================================================
set -euo pipefail

OWNER="${OWNER:-$(gh api user --jq .login)}"
APP_REPO="${OWNER}/auto-monitor"
DEPLOY_REPO="${OWNER}/auto-monitor-deployment"
REVIEWER_ID="$(gh api user --jq .id)"

echo "Owner: ${OWNER}   app: ${APP_REPO}   deployment: ${DEPLOY_REPO}"

# ---------------------------------------------------------------------------
echo "== 1. Actions hardening"
for repo in "$APP_REPO" "$DEPLOY_REPO"; do
  # GITHUB_TOKEN is read-only unless a workflow asks for more, and can't approve PRs
  gh api -X PUT "repos/${repo}/actions/permissions/workflow" \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false
  # Workflows from outside contributors' forks wait for a maintainer's approval
  gh api -X PUT "repos/${repo}/actions/permissions/fork-pr-contributor-approval" \
    -f approval_policy=all_external_contributors \
    || echo "   (fork approval policy not available on this account - set it in Settings > Actions)"
  echo "   ${repo}: default token read-only"
done

# ---------------------------------------------------------------------------
echo "== 2. Repository variables (not secret)"
gh variable set APP_REPO      --repo "$DEPLOY_REPO" --body "$APP_REPO"
gh variable set PUBLIC_URL    --repo "$DEPLOY_REPO" --body "http://localhost:3000"
gh variable set PUBLIC_WS_URL --repo "$DEPLOY_REPO" --body "ws://localhost:4000"

# ---------------------------------------------------------------------------
echo "== 3. Environments"
create_env() {
  local env="$1" body="$2"
  echo "$body" | gh api -X PUT "repos/${DEPLOY_REPO}/environments/${env}" --input - > /dev/null
  # only the main branch may deploy to this environment
  gh api -X POST "repos/${DEPLOY_REPO}/environments/${env}/deployment-branch-policies" \
    -f name=main -f type=branch > /dev/null 2>&1 || true
  echo "   ${env}: created (deployments from main only)"
}

create_env staging '{
  "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}
}'

create_env production "{
  \"wait_timer\": 0,
  \"prevent_self_review\": false,
  \"reviewers\": [{\"type\": \"User\", \"id\": ${REVIEWER_ID}}],
  \"deployment_branch_policy\": {\"protected_branches\": false, \"custom_branch_policies\": true}
}"
echo "   production: required reviewer = ${OWNER}"

# ---------------------------------------------------------------------------
echo "== 4. Environment secrets (random, different per environment)"
rand() { openssl rand -base64 33 | tr -d '/+=\n' | cut -c1-32; }

for env in staging production; do
  printf '%s' "$(rand)" | gh secret set MYSQL_PASSWORD      --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(rand)" | gh secret set MYSQL_ROOT_PASSWORD --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(rand)" | gh secret set PG_PASSWORD         --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(rand)$(rand)" | gh secret set INTERNAL_API_TOKEN --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(rand)" | gh secret set ADMIN_PASSWORD      --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(openssl rand -base64 32)" | gh secret set ENCRYPTION_KEY --env "$env" --repo "$DEPLOY_REPO"
  printf '%s' "$(openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt | openssl base64 -A)" \
    | gh secret set JWT_PRIVATE_KEY --env "$env" --repo "$DEPLOY_REPO"
  echo "   ${env}: 7 secrets set"
done

cat <<'EOF'

Done. Remaining MANUAL step (needs the web UI):
  - Create the fine-grained PAT (see guide, step 4.1) and store it with:
      gh secret set AUTO_MONITOR_PAT --repo <owner>/auto-monitor-deployment
Rotation: re-running this script generates and stores NEW values (old ones
are overwritten) - that is the credential rotation procedure.
EOF
