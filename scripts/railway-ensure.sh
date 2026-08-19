#!/usr/bin/env bash
set -euo pipefail
: "${RAILWAY_API_TOKEN:?RAILWAY_API_TOKEN is required}"
PROJECT_ID="${GUCCI_RAILWAY_PROJECT_ID:-1c311e7d-87d7-408f-8e9f-b855647a0e6d}"
SERVICE_ID="${GUCCI_RAILWAY_SERVICE_ID:-feb2269b-4dab-448b-8df5-eed2657eae56}"
ENVIRONMENT="${GUCCI_RAILWAY_ENVIRONMENT:-production}"
RW=(npx -y @railway/cli@latest)
common=(--project "$PROJECT_ID" --environment "$ENVIRONMENT" --service "$SERVICE_ID")
"${RW[@]}" link --project "$PROJECT_ID" --environment "$ENVIRONMENT" --service "$SERVICE_ID" >/dev/null

"${RW[@]}" variable set --service "$SERVICE_ID" --skip-deploys --json \
  'PORT=1' 'XUI_INTERNAL_PORT=2053' 'XUI_WEB_BASE_PATH=/gucci/' \
  'XUI_INITIAL_USERNAME=gucci' 'XUI_INITIAL_PASSWORD=gucci' 'XUI_FORCE_INITIAL_CREDENTIALS=true' \
  'XUI_DATA_ROOT=/data' 'XUI_DB_FOLDER=/etc/x-ui' 'XUI_DB_TYPE=sqlite' \
  'XUI_ENABLE_FAIL2BAN=false' 'XUI_BOOTSTRAP_INBOUND=true' \
  'GUCCI_INBOUND_PORT=1234' 'GUCCI_REALITY_SNI=play.google.com' \
  'XRAY_VMESS_AEAD_FORCED=false' 'TZ=Asia/Tehran' >/dev/null

# Keep exactly one Railway TCP proxy, always targeting Xray application port 1234.
PROXIES=$("${RW[@]}" tcp-proxy list "${common[@]}" --json)
printf '%s' "$PROXIES" | jq -r '.proxies[] | select(.applicationPort != 1234) | .id' | while read -r id; do
  [ -z "$id" ] || "${RW[@]}" tcp-proxy delete "$id" "${common[@]}" --yes --json >/dev/null
done
PROXIES=$("${RW[@]}" tcp-proxy list "${common[@]}" --json)
if ! printf '%s' "$PROXIES" | jq -e '.proxies | any(.applicationPort == 1234)' >/dev/null; then
  "${RW[@]}" tcp-proxy create "${common[@]}" --port 1234 --json >/dev/null
fi

# Keep the public Railway domain mapped to the branded gateway on application port 1.
DOMAINS=$("${RW[@]}" domain list "${common[@]}" --json)
DOMAIN=$(printf '%s' "$DOMAINS" | jq -r '(.serviceDomains[0].domain // .domains[0].domain // empty)')
if [ -z "$DOMAIN" ]; then
  "${RW[@]}" domain "${common[@]}" --port 1 --json >/dev/null
else
  "${RW[@]}" domain update "$DOMAIN" "${common[@]}" --port 1 --json >/dev/null
fi

# Pin the panel and Xray egress to Railway EU West (Amsterdam, Netherlands).
"${RW[@]}" scale --service "$SERVICE_ID" eu-west=1 us-west=0 --json >/dev/null
