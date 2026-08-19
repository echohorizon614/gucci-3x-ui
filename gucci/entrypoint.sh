#!/bin/sh
set -eu

PUBLIC_PORT="${PORT:-8080}"
PANEL_PORT="${XUI_INTERNAL_PORT:-2053}"
PANEL_PATH="${XUI_WEB_BASE_PATH:-/gucci/}"
INITIAL_USER="${XUI_INITIAL_USERNAME:-gucci}"
INITIAL_PASS="${XUI_INITIAL_PASSWORD:-gucci}"
DATA_ROOT="${XUI_DATA_ROOT:-/data}"

case "$PUBLIC_PORT:$PANEL_PORT" in *[!0-9:]*|:*) echo 'Invalid port configuration' >&2; exit 1;; esac
case "$PANEL_PATH" in /*/) ;; *) echo 'XUI_WEB_BASE_PATH must start and end with /' >&2; exit 1;; esac

persist_dir() {
  source="$1"; target="$2"
  mkdir -p "$target"
  if [ ! -L "$source" ]; then
    if [ -d "$source" ] && [ -z "$(find "$target" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
      cp -a "$source"/. "$target"/ 2>/dev/null || true
    fi
    rm -rf "$source"
    ln -s "$target" "$source"
  fi
}

mkdir -p "$DATA_ROOT" /tmp/nginx-proxy /tmp/nginx-client /run/nginx
persist_dir /etc/x-ui "$DATA_ROOT/x-ui"
persist_dir /root/cert "$DATA_ROOT/cert"
persist_dir /root/.acme.sh "$DATA_ROOT/acme"
persist_dir /var/log/x-ui "$DATA_ROOT/log"

DB=/etc/x-ui/x-ui.db
FIRST_BOOT=false
[ -f "$DB" ] || FIRST_BOOT=true

# Initialize the native database through the official binary. Credentials are
# only seeded once; later password/settings changes remain on the Railway volume.
if [ "$FIRST_BOOT" = true ]; then
  /app/x-ui setting -port "$PANEL_PORT" -username "$INITIAL_USER" -password "$INITIAL_PASS" -webBasePath "$PANEL_PATH" -listenIP 127.0.0.1
else
  # The reverse-proxy contract is stable even when the image is upgraded.
  /app/x-ui setting -port "$PANEL_PORT" -webBasePath "$PANEL_PATH" -listenIP 127.0.0.1
fi

# Native subscription endpoints stay untouched; only their public reverse-proxy
# URI is set so links generated inside 3X-UI use the Railway HTTPS domain.
# Factory defaults may not have a physical row yet, so this is a real upsert.
db_setting() {
  key=$(printf '%s' "$1" | sed "s/'/''/g")
  value=$(printf '%s' "$2" | sed "s/'/''/g")
  sqlite3 "$DB" "INSERT INTO settings(key,value) SELECT '${key}','${value}' WHERE NOT EXISTS (SELECT 1 FROM settings WHERE key='${key}'); UPDATE settings SET value='${value}' WHERE key='${key}';"
}
if [ -f "$DB" ]; then
  db_setting subListen 127.0.0.1
  db_setting subPort 2096
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    db_setting subURI "https://${RAILWAY_PUBLIC_DOMAIN}/sub/"
    db_setting subJsonURI "https://${RAILWAY_PUBLIC_DOMAIN}/json/"
    db_setting subClashURI "https://${RAILWAY_PUBLIC_DOMAIN}/clash/"
    db_setting subTitle "GUCCI Network"
    db_setting subSupportUrl "https://t.me/MR_GUCCI_YT"
  fi
fi

sed "s/__PORT__/${PUBLIC_PORT}/g" /app/gucci/nginx.conf.template >/tmp/nginx.conf
nginx -t -c /tmp/nginx.conf
nginx -c /tmp/nginx.conf -g 'daemon off;' &
NGINX_PID=$!
trap 'kill "$NGINX_PID" 2>/dev/null || true' INT TERM EXIT

export XUI_PORT="$PANEL_PORT"
export XUI_INIT_WEB_BASE_PATH="$PANEL_PATH"
export XUI_ENABLE_FAIL2BAN="${XUI_ENABLE_FAIL2BAN:-false}"

# Run the untouched upstream panel as PID 1 child. Railway health checks Nginx;
# if x-ui exits, this script exits and Railway restarts the service.
/app/DockerEntrypoint.sh &
XUI_PID=$!
wait "$XUI_PID"
STATUS=$?
kill "$NGINX_PID" 2>/dev/null || true
wait "$NGINX_PID" 2>/dev/null || true
exit "$STATUS"
