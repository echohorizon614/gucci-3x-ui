# 3X-UI v3.4.2 → v3.6.0 connectivity compatibility audit

Audit date: 2026-08-19

## Scope and method

This compares the official `MHSanaei/3x-ui` tags (the product is 3X-UI, not the unrelated S-UI project):

- v3.4.2: `f3a57d4c57fbcae94414138de42b7ef11dc513c8`
- v3.6.0: `c377dca27c23549cdf84e0ffd2d287a16bee577c`
- Range: 246 commits and 956 changed files

The audit used the tag source diff, release notes, generated default Xray configuration, Go dependency manifests, Xray-core's own tag diff, upstream regression reports, and controlled end-to-end A/B handshakes with an identical REALITY configuration.

## Root cause

The panel version itself is not the raw TCP data plane. The bundled external Xray-core process performs the REALITY/TLS/transport handshake and forwards user traffic.

The decisive runtime change is:

| Component | 3X-UI v3.4.2 | 3X-UI v3.6.0 |
|---|---:|---:|
| Bundled Xray executable | `v26.6.27` | `v26.7.28` |
| Xray Go module | commit `45cf2898` | commit `5ca6f4b7` |
| gRPC module | `1.81.1` | `1.82.1` |
| quic-go | `0.60.0` | `0.61.0` |
| sagernet/sing | `0.8.10` | `0.8.11` |
| uTLS | same revision | same revision |

Between Xray `26.6.27` and `26.7.28`, commit `af7eb68028732a8ee3c0e5d6ab2b8a657bb2e770` changed an empty REALITY `minClientVer` from **no version floor** to an implicit **`26.3.27`** floor. Older and third-party clients can therefore complete ordinary TLS to the REALITY destination but be rejected as proxy clients, producing the characteristic zero-byte/timeout/no-ping symptom.

Relevant upstream evidence:

- https://github.com/XTLS/Xray-core/commit/af7eb68028732a8ee3c0e5d6ab2b8a657bb2e770
- https://github.com/MHSanaei/3x-ui/issues/5922
- https://github.com/MetaCubeX/mihomo/issues/3042
- https://github.com/itdoginfo/podkop/issues/415

There are also independent REALITY interoperability and large-ClientHello/fragmentation reports. They explain why a single REALITY profile cannot honestly be called universal across every core and middlebox:

- https://github.com/XTLS/Xray-core/issues/6256
- https://github.com/SagerNet/sing-box/issues/4023

## Controlled A/B reproduction

An ephemeral local test used the same UUID, keypair, SNI, short ID, destination, `xtls-rprx-vision` flow, and Xray `25.5.16` client. Only the server core/default changed:

| Server condition | Result |
|---|---|
| Xray `26.6.27`, `minClientVer` omitted | success |
| Xray `26.7.28`, `minClientVer` omitted | failed during TLS/REALITY |
| Xray `26.7.28`, explicit `minClientVer: 1.8.2` | success |
| Xray `26.7.28`, explicit `minClientVer: 1.0.0` | success |

This isolates the version-floor behavior from DNS, Railway, panel UI, UUID, key, SNI, and routing variables.

## Other material differences reviewed

- The shipped base routing rules are otherwise the same. v3.6.0 adds a second private-range block in the Freedom outbound's `finalRules`; v3.4.2 already blocks `geoip:private` in routing, so this is defense-in-depth rather than the cause of public-Internet handshakes failing.
- Xray renamed the stream key `network` to `method`; v3.6.0 contains compatibility normalization for it.
- XHTTP client defaults changed, including a reduction of default `maxConnections` from 6 to 3. This applies to XHTTP, not the production TCP/REALITY or WS profiles.
- v3.6.0 contains multiple DNS, routing, subscription, VLESS-flow, forwarded-host, runtime lifecycle, and malformed-config fixes. Reverting the panel would discard those improvements and is unnecessary.
- The REALITY `minClientVer` field is server-side and is not carried in client share links. Recreating UUIDs, keys, SNI, or SpiderX does not fix an implicit server version floor.

## Applied compatibility design

The production image keeps the complete 3X-UI v3.6.0 panel while restoring the relevant v3.4.2 behavior:

1. Runtime Xray is pinned to official `v26.6.27` and verified with SHA-256 `b3e5902d06d6282fe53cfa2fc426058b9aeaa429b2c812e20887cd47f26d08bf`.
2. Blank legacy REALITY `minClientVer` values are normalized to explicit `1.0.0` at startup; deliberately configured non-empty values are never overwritten.
3. A VLESS WebSocket + public TLS/443 compatibility profile is included in the same subscription and sorted first. This covers sing-box and networks that block the Railway raw TCP Proxy port.
4. The original REALITY profile remains available for Xray/Mihomo clients and networks where it performs better.
5. Subscription responses are no-store and advertise a one-hour refresh interval.
6. `/healthz` checks the panel and both local TCP targets (`1234`, `1235`) instead of returning a constant success. Repeated failures stop x-ui so Railway can recover it using the persistent `/GUCCI` volume.
7. CI builds the full v3.6.0 image and executes the final image's Xray binary to assert `Xray 26.6.27`, preventing an upstream source sync from silently reintroducing the regression.

## Production verification

The following were verified with real proxy handshakes and downloads rather than port-only probes:

- Xray `26.7.28` → REALITY: success
- Mihomo `1.19.30` → REALITY: success
- Xray `25.5.16` → WS/TLS/443: success
- Mihomo `1.19.30` → WS/TLS/443: success
- sing-box `1.13.19` and `1.12.17` → WS/TLS/443: success
- 20/20 sequential requests and 16/16 concurrent requests: success
- 20 MB sustained download: success
- First subscription profile (WS/TLS/443), 10 MB transfer: HTTP 200
- Health endpoint: HTTP 200 only after panel and configured TCP targets are listening

No single test location can physically represent every ISP or mobile operator. The two-transport design avoids claiming that REALITY/raw TCP can bypass every middlebox while retaining the fastest option where it is supported.
