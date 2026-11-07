#!/usr/bin/env bash
# Smoke test: is the deployed auto-monitor actually working end-to-end?
set -euo pipefail
cd "$(dirname "$0")"

check() {
  local name="$1" url="$2"
  if curl -fsS -m 10 -o /dev/null "$url"; then echo "OK   $name"; else echo "FAIL $name ($url)"; return 1; fi
}

check "frontend /api/_health"  http://127.0.0.1:3000/api/_health
check "ws-gateway /readyz"     http://127.0.0.1:4000/readyz

docker compose --env-file .env exec -T backend \
  wget -qO- http://127.0.0.1:8080/actuator/health/readiness | grep -q UP && echo "OK   backend readiness"
docker compose --env-file .env exec -T agent \
  python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/readyz', timeout=5)" && echo "OK   agent readiness"

# Functional check: log in through the public entry point and receive a JWT.
body=$(jq -n --arg u admin --arg p "${ADMIN_PASSWORD:?}" '{username: $u, password: $p}')
if curl -fsS -m 10 -H 'Content-Type: application/json' -d "$body" \
     http://127.0.0.1:3000/api/v1/auth/login | jq -e '.token | length > 20' >/dev/null; then
  echo "OK   login returns a JWT"
else
  echo "FAIL login"; exit 1
fi
echo "Smoke test passed"
