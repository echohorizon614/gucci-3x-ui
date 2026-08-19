# 3X-UI v3.4.2 → v3.6.0 — Upgrade Complete ✅

**Upgrade date:** 2026-08-19
**Status:** ✅ Successfully upgraded to v3.6.0

This upgrade was performed by rebasing on the official `MHSanaei/3x-ui` tag `v3.6.0`
and reapplying GUCCI-specific customizations (Railway deployment, branding, entrypoint).

## What changed

| Component | Before | After |
|-----------|--------|-------|
| 3X-UI panel | v3.4.2 | **v3.6.0** |
| Bundled Xray | v26.6.27 | **v26.7.28** |
| Go version | 1.26.4 | **1.26.5** |
| gRPC | 1.81.1 | **1.82.1** |
| Frontend | React 19.2.7 | **React 19.2.8** |

## Key fixes & features in v3.6.0

- 🧭 **Trend-First Overview** — redesigned dashboard with sparklines & throughput charts
- 🛡 **xray-core v26.7.28** — absorbs the XMC finalmask breaking change end-to-end
- 🔗 **Subscription correctness** — link/format fixes, identity tokens, live online status
- 🔐 **Security hardening** — `openapi.json` behind auth, write-only node tokens, sourcemaps removed
- 🧹 **Two large audit sweeps** — 70 fixes across the entire codebase
- 🗃 **Data integrity** — online SQLite snapshots, legacy `tgId` repair, orphan cleanup

## Rollback

If needed, rollback instructions are available in the `~/sanaei-upgrade/` package.
