# Admin stats access plan: terminal, agents, and the bot

> Started 2026-10-15 from a user request: read the backend admin stats (cost, revenue, margin, MRR, devices, usage, client errors) from Claude Code and from Ian's Grok Bot (xAI's desktop agent on his Omarchy machine, "wherever") without opening the `/admin` dashboard. The first ask was "an MCP for admin stats". The answer is a script and a read-only token, not an MCP; the reasoning is below and the MCP question is deferred to the server planned in [cloud-sync-plan.md](cloud-sync-plan.md).

## Status

| Step | Status | Notes |
|---|---|---|
| Terminal client `scripts/admin-stats.mjs` in `miniti-api` | **Built and verified 2026-10-15** against production | Node 20, no dependencies. `summary`, `ledger`, `costs`, `usage`, `devices`, `events`, `logout`. Logs in with `ADMIN_SECRET_KEY` from `.env` through `POST /api/admin/session`, caches the 12 h cookie in `scripts/.admin-session` (mode 600, gitignored). Prefers `ADMIN_READ_TOKEN` as a bearer when present. Uncommitted. |
| Claude Code skill `admin-stats` | **Built 2026-10-15** | Source `miniti-api/.claude/skills/admin-stats/SKILL.md`; `miniti/.claude/skills/admin-stats` is a symlink to it (the `.claude` folder here is gitignored). Permission rules for the script are in both repos' `settings.local.json`. |
| Backend: read-only bearer `ADMIN_READ_TOKEN` on `GET /api/admin/*` | **Deployed 2026-10-15** (commit 3aa68f2 on `main`, auto deploy) | `lib/adminAuth.ts`: `readBearer`, `verifyAdminReadToken`, and a branch at the top of `checkAdminAuth` for non-mutation requests only. Constant-time compare, wrong token burns an `admin_login` limiter slot (5/min per network bucket), audit line `admin_token_read`. 4 new tests; 470 backend tests green. Docs: `02-environment.md`, `04-api-reference.md`. |
| Deploy: set `ADMIN_READ_TOKEN` in Vercel Production, deploy `miniti-api`, smoke test | **Done 2026-10-15** | Ian generated the token into `miniti-api/.env`; Claude set it in Vercel Production (sensitive) and ran the smoke curls after the deploy: bearer read 200, wrong token `401 unauthorized`, bearer POST `401 admin_session_required`, no auth 401. Original steps kept for a rotation: generate with `openssl rand -hex 32`. Set the variable **before** deploying (the path is off while it is unset, so the order is only about the smoke test). Smoke: `curl -s -H "Authorization: Bearer $T" https://api.miniti.app/api/admin/ledger \| jq .fetched_at`, then a wrong token answers `401 unauthorized`, then a `POST /api/admin/devices` with only the bearer answers `401 admin_session_required`. |
| Bot access: curl cookbook `scripts/admin-stats-curl.md` | **Written 2026-10-15**, every jq line verified against live JSON | Any agent with `curl` and `jq` and the token in `MINITI_ADMIN_READ_TOKEN`. How Grok Bot takes it (pasted instructions, a skill file, an MCP wrapper) is Ian's call; nothing in the cookbook depends on the host. |
| Admin MCP tools | deferred | Only worth it when a consumer speaks MCP and nothing else. Claude Code runs the script; Grok Bot runs `curl`. If the `/api/mcp` server in [cloud-sync-plan.md](cloud-sync-plan.md) ships, an admin tool set (`admin_summary`, `admin_ledger`, `admin_devices`, `admin_events`) behind the same bearer is a half-day slice on top of it. |

## What Ian gets

- "How's miniti doing?" in Claude Code answers from live numbers in one command, with cost, revenue, margin, MRR, devices by platform and version, and 7 and 30 day usage, in about 3 seconds.
- Any specific number the dashboard shows is one command away as JSON, including per-device records and client diagnostics with filters.
- The same five endpoints answer the bot from anywhere once the read token is deployed, with nothing but `curl` and a secret on the bot's side.
- The admin secret never leaves `.env` and Vercel. The bot only ever holds a token that cannot change anything.

## Why not an MCP

An MCP server is the right shape when the consumer is an MCP client and the data has no other door. Neither holds here:

- Claude Code can run a script. A script with a skill file gives it the same five tools with less code than an MCP server and no process to keep alive.
- Grok Bot can run a shell. Five `curl` lines with a bearer need no server on our side; if it turns out to prefer MCP, a wrapper over the same five calls is the deferred slice below.
- The stats already have a door: the admin HTTP routes. The only thing missing was a way for a machine to authenticate without a browser session. That is a 30-line auth change, not a protocol.

A remote MCP on `api.miniti.app` for admin stats would need its own transport, its own auth, and a deployment, to expose the same five calls. If the meetings MCP server from the cloud sync plan ships, admin tools ride on it for almost nothing. Until then, there is no consumer that needs it.

## Design

### Auth, two paths, one guard

`checkAdminAuth` is the single guard on every admin route. It now has two ways to say yes:

1. **Session cookie** (unchanged): the dashboard and the script's fallback. Issued by `POST /api/admin/session` from `ADMIN_SECRET_KEY`, 12 h, revocable, mutations also need a same-origin `Origin`.
2. **Read token** (new): `Authorization: Bearer <ADMIN_READ_TOKEN>` on a non-mutation request. Compared constant time after hashing both sides, like the admin secret. A request that carries a bearer and asks for a mutation never consults the token; it falls through to the cookie check and fails with `admin_session_required`. So the token cannot label, disable, or rotate anything, whatever route is added later, as long as mutations keep passing `{ mutation: true }`.

Why a second secret rather than the admin secret on the bot: the admin secret can mutate and sign in to the dashboard. A desktop agent's config is a wider surface than Vercel's env. A leaked read token exposes the stats; a leaked admin secret exposes the device registry's controls.

Why no expiry or revocation list: the token has no session. Rotation is changing the env var, which takes effect on the next deploy. The limiter stops online guessing; the token is 256 bits.

Why the bearer path counts failures against the login limiter: a wrong token is the same event as a wrong password. Successes are never counted, so a bot polling every few minutes never trips it.

### The script

`scripts/admin-stats.mjs` is the reference client and the only one the Claude Code skill uses. Auth order: `ADMIN_READ_TOKEN` if present (env or `.env`), otherwise the cookie dance with `ADMIN_SECRET_KEY`. It reads `.env` with Next's precedence (`.env.local` over `.env`, last line wins), which matters because Ian's `.env` carries two `ADMIN_SECRET_KEY` lines and only the later one matches production. It never prints a secret, token, or cookie. `summary` is the only command that computes anything; everything else is the endpoint's JSON verbatim so the API reference stays the source of truth.

### Where the secrets live

| Secret | Where | Who uses it |
|---|---|---|
| `ADMIN_SECRET_KEY` | Vercel env, `miniti-api/.env` | Dashboard login, the script's fallback |
| `ADMIN_SESSION_SECRET` | Vercel env only | Cookie signing |
| `ADMIN_READ_TOKEN` | Vercel env; `miniti-api/.env` (the script reads it); on the bot's machine as `MINITI_ADMIN_READ_TOKEN` | Bot, script |

## Manual checks owed

- [x] After deploy: the smoke curls in the status table (2026-10-15).
- [ ] Grok Bot: give it the cookbook and the token, ask "how is miniti doing", confirm it quotes the ledger with the `fetched_at` time and never prints the token.
- [ ] Rotate `ADMIN_READ_TOKEN` once to confirm the old value answers `401` on the next deploy.
