#!/bin/sh
set -eu

[ "${XUI_BOOTSTRAP_INBOUND:-true}" = "true" ] || exit 0
PANEL_PORT="${XUI_INTERNAL_PORT:-2053}"
PANEL_PATH="${XUI_WEB_BASE_PATH:-/gucci/}"
PANEL_PATH="/${PANEL_PATH#/}"; PANEL_PATH="${PANEL_PATH%/}"
BASE="http://127.0.0.1:${PANEL_PORT}${PANEL_PATH}"
COOKIE=/tmp/gucci-bootstrap-cookie
CSRF_JSON=/tmp/gucci-bootstrap-csrf
INBOUND_PORT="${GUCCI_INBOUND_PORT:-1234}"
REALITY_SNI="${GUCCI_REALITY_SNI:-play.google.com}"
PROXY_DOMAIN="${RAILWAY_TCP_PROXY_DOMAIN:-}"
PROXY_PORT="${RAILWAY_TCP_PROXY_PORT:-}"
ADMIN_USER="${XUI_INITIAL_USERNAME:-gucci}"
ADMIN_PASS="${XUI_INITIAL_PASSWORD:-gucci}"
rm -f "$COOKIE" "$CSRF_JSON"

for _ in $(seq 1 90); do
  if curl -fsS -c "$COOKIE" "$BASE/csrf-token" >"$CSRF_JSON" 2>/dev/null; then break; fi
  sleep 2
done
TOKEN=$(jq -r '.obj // empty' "$CSRF_JSON" 2>/dev/null || true)
[ -n "$TOKEN" ] || { echo 'GUCCI bootstrap: panel did not become ready' >&2; exit 1; }

api_post() {
  path="$1"; body="${2:-{}}"
  curl -fsS -b "$COOKIE" -c "$COOKIE" -H 'Content-Type: application/json' -H "X-CSRF-Token: $TOKEN" --data "$body" "$BASE$path"
}
api_get() { curl -fsS -b "$COOKIE" "$BASE$1"; }

LOGIN=$(api_post /login "$(jq -nc --arg u "$ADMIN_USER" --arg p "$ADMIN_PASS" '{username:$u,password:$p,twoFactorCode:""}')")
[ "$(printf '%s' "$LOGIN" | jq -r '.success')" = true ] || { echo 'GUCCI bootstrap: login failed' >&2; exit 1; }

LIST=$(api_get /panel/api/inbounds/list)
INBOUND=$(printf '%s' "$LIST" | jq -c --argjson p "$INBOUND_PORT" '.obj[]? | select(.protocol=="vless" and .port==$p)' | head -1)
if [ -n "$INBOUND" ]; then
  ID=$(printf '%s' "$INBOUND" | jq -r '.id')
  PAYLOAD=$(printf '%s' "$INBOUND" | jq -c \
    --arg sni "$REALITY_SNI" --arg proxy "$PROXY_DOMAIN" --argjson p "$INBOUND_PORT" '
      .remark="GUCCI-REALITY-TCP-1234-NL" |
      .enable=true | .listen="" | .port=$p | .protocol="vless" |
      .shareAddrStrategy="listen" | .shareAddr=$proxy |
      .settings.clients=((.settings.clients // []) | map(.limitIp=(.limitIp // 0) | .enable=true)) |
      .streamSettings.network="tcp" | .streamSettings.security="reality" |
      .streamSettings.realitySettings.target=($sni+":443") |
      .streamSettings.realitySettings.serverNames=[$sni] |
      .streamSettings.realitySettings.settings.serverName=$sni |
      del(.clientStats,.fallbackParent)
    ')
  RESULT=$(api_post "/panel/api/inbounds/update/$ID" "$PAYLOAD")
else
  XRAY=$(find /app/bin -maxdepth 1 -type f -name 'xray-linux-*' | head -1)
  [ -x "$XRAY" ] || { echo 'GUCCI bootstrap: xray binary missing' >&2; exit 1; }
  KEYS=$($XRAY x25519)
  PRIVATE=$(printf '%s\n' "$KEYS" | awk -F': ' '/PrivateKey/{print $2;exit}')
  PUBLIC=$(printf '%s\n' "$KEYS" | awk -F': ' '/Password|PublicKey/{print $2;exit}')
  UUID=$($XRAY uuid | head -1)
  SID=$(openssl rand -hex 8)
  SUBID=$(openssl rand -hex 8)
  [ -n "$PRIVATE" ] && [ -n "$PUBLIC" ] && [ -n "$UUID" ]
  PAYLOAD=$(jq -nc --arg sni "$REALITY_SNI" --arg proxy "$PROXY_DOMAIN" --arg priv "$PRIVATE" --arg pub "$PUBLIC" --arg uuid "$UUID" --arg sid "$SID" --arg sub "$SUBID" --argjson p "$INBOUND_PORT" '
    {up:0,down:0,total:0,remark:"GUCCI-REALITY-TCP-1234-NL",enable:true,expiryTime:0,trafficReset:"never",trafficResetDay:1,
     listen:"",port:$p,protocol:"vless",tag:("in-"+($p|tostring)+"-tcp"),shareAddrStrategy:"listen",shareAddr:$proxy,
     settings:{clients:[{id:$uuid,flow:"xtls-rprx-vision",email:"gucci-user",limitIp:0,totalGB:0,expiryTime:0,enable:true,tgId:"",subId:$sub,reset:0}],decryption:"none",fallbacks:[]},
     streamSettings:{network:"tcp",security:"reality",externalProxy:[],tcpSettings:{acceptProxyProtocol:false,header:{type:"none"}},realitySettings:{show:false,xver:0,target:($sni+":443"),serverNames:[$sni],privateKey:$priv,minClientVer:"",maxClientVer:"",maxTimediff:0,shortIds:[$sid],mldsa65Seed:"",settings:{publicKey:$pub,fingerprint:"chrome",serverName:$sni,spiderX:"/",mldsa65Verify:""}}},
     sniffing:{enabled:true,destOverride:["http","tls","quic"],metadataOnly:false,routeOnly:false}}
  ')
  RESULT=$(api_post /panel/api/inbounds/add "$PAYLOAD")
  ID=$(printf '%s' "$RESULT" | jq -r '.obj.id // .obj.Id // empty')
fi
[ "$(printf '%s' "$RESULT" | jq -r '.success')" = true ] || { echo "GUCCI bootstrap: inbound write failed" >&2; exit 1; }
[ -n "$ID" ] || ID=$(api_get /panel/api/inbounds/list | jq -r --argjson p "$INBOUND_PORT" '.obj[] | select(.protocol=="vless" and .port==$p) | .id' | head -1)

if [ -n "$PROXY_DOMAIN" ] && [ -n "$PROXY_PORT" ] && [ -n "$ID" ]; then
  ENDPOINT="${PROXY_DOMAIN}:${PROXY_PORT}"
  HOSTS=$(api_get "/panel/api/hosts/byInbound/$ID")
  GROUP=$(printf '%s' "$HOSTS" | jq -c '.obj[0] // empty')
  if [ -n "$GROUP" ]; then
    GID=$(printf '%s' "$GROUP" | jq -r '.groupId')
    HPAYLOAD=$(printf '%s' "$GROUP" | jq -c --arg endpoint "$ENDPOINT" --arg sni "$REALITY_SNI" --argjson port "$PROXY_PORT" --argjson iid "$ID" '
      .inboundIds=[$iid] | .hosts=[$endpoint] | .port=$port | .security="same" | .sni=$sni |
      .fingerprint="chrome" | .overrideSniFromAddress=false | .keepSniBlank=false | .isDisabled=false | .isHidden=false | .remark="GUCCI TCP 1234"
    ')
    HRES=$(api_post "/panel/api/hosts/update/$GID" "$HPAYLOAD")
  else
    HPAYLOAD=$(jq -nc --arg endpoint "$ENDPOINT" --arg sni "$REALITY_SNI" --argjson port "$PROXY_PORT" --argjson iid "$ID" '
      {groupId:"",inboundIds:[$iid],hosts:[$endpoint],sortOrder:0,remark:"GUCCI TCP 1234",serverDescription:"",isDisabled:false,isHidden:false,tags:[],port:$port,security:"same",sni:$sni,hostHeader:"",path:"",alpn:[],fingerprint:"chrome",overrideSniFromAddress:false,keepSniBlank:false,pinnedPeerCertSha256:[],verifyPeerCertByName:"",allowInsecure:false,echConfigList:"",muxParams:"",sockoptParams:"",finalMask:"",vlessRoute:"",excludeFromSubTypes:[],nodeGuids:[],mihomoIpVersion:"",mihomoX25519:false,shuffleHost:false}
    ')
    HRES=$(api_post /panel/api/hosts/add "$HPAYLOAD")
  fi
  [ "$(printf '%s' "$HRES" | jq -r '.success')" = true ] || { echo 'GUCCI bootstrap: host override failed' >&2; exit 1; }
fi

api_post /panel/api/server/restartXrayService '{}' >/dev/null
rm -f "$COOKIE" "$CSRF_JSON"
echo "GUCCI bootstrap: VLESS Reality TCP ${INBOUND_PORT}, SNI ${REALITY_SNI}, IP-limit UI enabled"
