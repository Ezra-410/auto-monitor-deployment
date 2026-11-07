#!/usr/bin/env bash
# =============================================================================
# Branch protection for "main" on both repositories (Milestone 6).
# Run it LAST - after this, nobody (not even you) pushes directly to main;
# every change goes through a pull request + green checks + code-owner review.
#
#   bash scripts/protect-branches.sh
#   ENFORCE_ADMINS=true bash scripts/protect-branches.sh   # also binds admins
#
# ENFORCE_ADMINS=false (default) lets the repo admin override in an emergency
# (the override is recorded). Use "true" once a second reviewer exists.
# =============================================================================
set -euo pipefail

OWNER="${OWNER:-$(gh api user --jq .login)}"
ENFORCE_ADMINS="${ENFORCE_ADMINS:-false}"

protect() {
  local repo="$1" check="$2"
  gh api -X PUT "repos/${repo}/branches/main/protection" --input - > /dev/null <<JSON
{
  "required_status_checks": { "strict": true, "contexts": ["${check}"] },
  "enforce_admins": ${ENFORCE_ADMINS},
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
  echo "${repo}: main protected (required check: '${check}', code-owner review, no force-push)"
}

protect "${OWNER}/auto-monitor"            "CI evidence"
protect "${OWNER}/auto-monitor-deployment" "CDL gate"
