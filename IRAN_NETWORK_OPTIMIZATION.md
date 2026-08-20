# 🇮🇷 GUCCI 3X-UI — Iran Network Optimization Guide

> Comprehensive tuning for reliable connectivity across all Iranian operators
> and ISPs. Applied on top of 3X-UI v3.6.0.

---

## What's already applied in this build

### 1. Iran traffic → Direct routing (built into the panel defaults)

The default Xray routing now sends **Iranian domestic traffic directly**
instead of through the tunnel:

```json
{ "ip": ["geoip:ir"], "outboundTag": "direct", "type": "field" },
{ "domain": ["geosite:ir"], "outboundTag": "direct", "type": "field" }
```

**Why this matters for Iranian ISPs:**

- Banking, government and domestic services (many of which sit inside the
  national internet) no longer round-trip through the proxy.
- Lower latency: domestic traffic stays in-country.
- More stability: the tunnel is only used for international traffic.
- MCI / MTN Irancell / RighTel users see a big improvement because their
  national links are fast while international routes are the bottleneck.

### 2. REALITY compatibility preserved (entrypoint)

The container entrypoint normalizes every REALITY inbound's `minClientVer` to
`1.0.0` when unset/empty, preserving the broad client compatibility that
Xray 26.7.x otherwise changes to an implicit `26.3.27` floor.

### 3. Client limits (new in this build)

- **Traffic Limit (GB)** — enforced by the panel's traffic job (client auto-disables on quota).
- **Speed Limit (Mbps)** — new per-client field, enforced in Clash/Mihomo subscriptions via `down`/`up`.

---

## Recommended inbound setup per Iranian operator

### Mobile operators

| Operator | Recommended protocol | Notes |
|---|---|---|
| **MCI — همراه اول** | VLESS + REALITY (TCP) | REALITY mimics real TLS; MCI deep-packet-inspection treats it as normal HTTPS. Keep `serverName` an unblocked site (e.g. `dl.google.com`). |
| **MTN Irancell — ایرانسل** | VLESS + REALITY (TCP) or VLESS+WS+TLS (CDN) | Both work. CDN path helps when IP is throttled. |
| **RighTel — رایتل** | VLESS + REALITY (TCP) | Same as MCI. |
| **Shatel Mobile / Aptel / Samantel / LotusTel / Spadan** | VLESS + REALITY (TCP) | All behave like mobile broadband; TCP + REALITY is the safest baseline. |

### Fixed internet / FCP / ISP networks

| Network | Recommended approach |
|---|---|
| **TCI / مخابرات** | REALITY on TCP 443 or 1234. Avoid UDP-heavy transports (MCI/TCI throttle UDP). |
| **Shatel / Asiatech / Pars Online / HiWEB** | REALITY works directly; CDN (Cloudflare) optional for extra stability. |
| **Pishgaman / Sabanet / Fanap / Respina / Mobinnet / Afranet / others** | Same: REALITY TCP. These are datacenter-grade links; speed is rarely the issue. |

### Key principles for Iranian networks

1. **Use REALITY, not plain TLS.** Plain TLS SNI is fingerprintable and blocked
   on several Iranian ISPs. REALITY with `fingerprint: chrome` + a real SNI
   (Google Play, Yahoo, etc.) passes as normal HTTPS.
2. **Prefer TCP** for mobile operators — UDP/QUIC is often throttled or blocked.
   Hysteria2 is only recommended on fixed lines.
3. **Port choices:** 443 (looks like HTTPS), 1234 (used by the GUCCI preset),
   or 2053/2083 (CDN-friendly). Avoid 80/8080 which Iranian ISPs often flag.
4. **Keep `flow: xtls-rprx-vision`** for VLESS+REALITY — best throughput on
   the XTLS path.
5. **Don't block the "bittorrent" rule off** — it keeps the panel from being
   flagged by ISP traffic shaping.
6. **Subscription links** should use the HTTPS Railway domain so clients
   update over TLS (already configured in the entrypoint).

---

## Verifying connectivity

After deployment, from an Iranian device run:

```bash
# Ping the tunnel (any device)
ping -c 4 YOUR_RAILWAY_DOMAIN

# Latency check
curl -o /dev/null -s -w "connect: %{time_connect}s\ntotal: %{time_total}s\n" https://YOUR_RAILWAY_DOMAIN/gucci/

# Throughput (on the client side, through the VPN)
# Use the panel's per-client realtime speed meter, or iperf3 through the tunnel
```

**Target values (Iran → Railway):**
- REALITY TCP connect: < 250 ms typical, < 400 ms acceptable
- Speed: depends on the Railway region; Netherlands (ams) is the default and
  gives good Iran ↔ EU routing.

---

## Operator-specific notes

- **MCI**: blocks many foreign IP ranges at peak hours. If a server drops,
  redeploy the inbound on another port — the panel generates fresh ports via
  the GUCCI port generator. MCI also throttles UDP aggressively → TCP/REALITY.
- **MTN Irancell**: generally the most permissive operator; REALITY and CDN
  both work. Great for WS+TLS+CDN fallback testing.
- **RighTel**: similar to MCI; TCP + REALITY is the recommendation.
- **TCI (ADSL/Fiber)**: direct international links are decent; REALITY direct
  is usually enough, no CDN needed.
- **FCP (Fiber Communication Provider)**: same as TCI.
- **Datacenter ISPs** (Pishgaman, Fanap, Mobinnet, Respina): high capacity;
  Hysteria2 or VLESS+REALITY both fine.

---

## If a specific network fails

1. Check the panel's inbound traffic graph — if 0 bytes, the client isn't
   reaching the server (routing/port issue).
2. Try switching the SNI (`serverName`) to another major site (Google Play,
   Yahoo, Apple) via the inbound edit → REALITY settings.
3. Try changing the inbound port (use the GUCCI port generator for a fresh pair).
4. On mobile operators, force the client to TCP + REALITY (no UDP-based options).
5. Use `x-ui log` in the container to see xray-core errors:
   ```bash
   docker logs <container> 2>&1 | grep -i "reality\|reject\|error"
   ```
