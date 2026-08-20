# 🇮🇷 GUCCI 3X-UI — Iran Network Optimization Guide

> Comprehensive tuning for reliable connectivity across all Iranian operators
> and ISPs. Applied on top of 3X-UI v3.6.0.

---

## ⚠️ IMPORTANT — Do NOT use `geoip:ir` / `geosite:ir` in routing rules

The GUCCI container ships **custom Iran geo files** (`geoip_IR.dat`,
`geosite_IR.dat`) alongside the standard ones. Xray's geodata loader looks for
category `IR` inside `geosite.dat`, which the custom file layout does not
satisfy — using `geosite:ir` in a routing rule makes **xray-core fail to
start** with:

```
illegal domain rule: geosite:ir > failed to check code IR from geosite.dat > EOF
```

**If you want Iran direct routing, add it in the panel UI**
(⚠️ *Panel Settings → Xray Configuration → Routing* → add a rule) only after
verifying the rule parses. A broken rule takes the whole core down, so prefer
protocol/IP-limit based rules over geoip country rules on this container.

---

## What IS applied in this build (safe & verified)

### 1. Client limits (new in this build)

- **Traffic Limit (GB)** — enforced by the panel's traffic job (client
  auto-disables on quota).
- **Speed Limit (Mbps)** — new per-client field, enforced in Clash/Mihomo
  subscriptions via `down`/`up`.

### 2. Dynamic relative timestamps

- Client expiry, node heartbeats and inbound expiry now show localized
  relative time: *just now, 5 minutes ago, 1 hour ago, yesterday, 3 days ago…*
  instead of stale day-rounded labels.

### 3. REALITY compatibility preserved (entrypoint)

The container entrypoint normalizes every REALITY inbound's `minClientVer` to
`1.0.0` when unset/empty, preserving broad client compatibility that Xray
26.7.x otherwise changes to an implicit `26.3.27` floor.

---

## Recommended inbound setup per Iranian operator

### Mobile operators

| Operator | Recommended protocol | Notes |
|---|---|---|
| **MCI — همراه اول** | VLESS + REALITY (TCP) | REALITY mimics real TLS; MCI DPI treats it as normal HTTPS. Keep `serverName` an unblocked site (e.g. `dl.google.com`). |
| **MTN Irancell — ایرانسل** | VLESS + REALITY (TCP) or VLESS+WS+TLS (CDN) | Both work. CDN path helps when IP is throttled. |
| **RighTel — رایتل** | VLESS + REALITY (TCP) | Same as MCI. |
| **Shatel Mobile / Aptel / Samantel / LotusTel / Spadan** | VLESS + REALITY (TCP) | Mobile broadband; TCP + REALITY is the safest baseline. |

### Fixed internet / FCP / ISP networks

| Network | Recommended approach |
|---|---|
| **TCI / مخابرات** | REALITY on TCP 443 or 1234. Avoid UDP-heavy transports (MCI/TCI throttle UDP). |
| **Shatel / Asiatech / Pars Online / HiWEB** | REALITY direct; CDN (Cloudflare) optional for extra stability. |
| **Pishgaman / Sabanet / Fanap / Respina / Mobinnet / Afranet / others** | Same: REALITY TCP. Datacenter-grade links; speed rarely an issue. |

### Key principles for Iranian networks

1. **Use REALITY, not plain TLS.** Plain TLS SNI is fingerprintable and blocked
   on several Iranian ISPs. REALITY with `fingerprint: chrome` + a real SNI
   (Google Play, Yahoo, etc.) passes as normal HTTPS.
2. **Prefer TCP** for mobile operators — UDP/QUIC is often throttled or blocked.
   Hysteria2 is only recommended on fixed lines.
3. **Port choices:** 443 (looks like HTTPS), 1234 (GUCCI preset),
   or 2053/2083 (CDN-friendly). Avoid 80/8080 which Iranian ISPs often flag.
4. **Keep `flow: xtls-rprx-vision`** for VLESS+REALITY — best throughput on
   the XTLS path.
5. **Don't disable the bittorrent block** — keeps the panel from being flagged
   by ISP traffic shaping.
6. **Subscription links** use the HTTPS Railway domain so clients update over
   TLS (already configured in the entrypoint).

---

## Verifying connectivity

After deployment, from an Iranian device run:

```bash
ping -c 4 YOUR_RAILWAY_DOMAIN

curl -o /dev/null -s -w "connect: %{time_connect}s\ntotal: %{time_total}s\n" https://YOUR_RAILWAY_DOMAIN/gucci/
```

**Target values (Iran → Railway):**
- REALITY TCP connect: < 250 ms typical, < 400 ms acceptable
- Speed depends on Railway region; Netherlands (ams) is the default.

---

## If a specific network fails

1. Check the panel's inbound traffic graph — 0 bytes means the client isn't
   reaching the server.
2. Switch the REALITY `serverName` to another major site (Google Play, Yahoo,
   Apple) via inbound edit → REALITY settings.
3. Change the inbound port (use the GUCCI port generator for a fresh pair).
4. On mobile operators, force TCP + REALITY (no UDP-based options).
5. View container logs for xray-core errors:
   ```bash
   docker logs <container> 2>&1 | grep -i "reality\|reject\|error"
   ```
