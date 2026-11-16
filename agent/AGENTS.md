# Coding Agent Instructions — FIBPOP

## Required reading order

1. `README.md`
2. `game-rules/Original_Game_Rules_EN.md`
3. `docs/Rules_Clarifications_and_Decisions.md`
4. `shared/card_catalog_v1.json`
5. `docs/Architecture.md`
6. `docs/Development_Plan.md`
7. `docs/API_and_State_Contracts.md`

## Nonnegotiable constraints

- Do not introduce mechanics from any unrelated tabletop game or add new roles.
- Do not silently alter the 72-card list, quantities, or win conditions. Flag needed changes in a decision log and implement a documented behavior only when the rules register explicitly allows it.
- No main board/pawns. All online role/deck secrecy is server-enforced.
- No direct Node-only HTTP/socket framework; use **Hono for Worker HTTP** and **native Durable Objects hibernating WebSockets**.
- Keep game rules portable pure TypeScript. Dart offline implementation must pass the same shared fixtures.
- No paid gameplay advantages. Do not implement ads, IAP, or freeform chat before corresponding milestone.
- Build one milestone at a time, run tests, explain observed outputs and remaining risk.
- Keep credentials as secure bindings/environment secrets; never hardcode private keys or cloud tokens.

## Suggested monorepo

```text
fibpop/
  apps/mobile/               # Flutter Android / iOS / future web
  services/backend/          # Hono Worker + Durable Objects
  packages/game-engine/      # Pure TypeScript rules
  shared/                    # Versioned card catalog + golden test fixtures
  docs/                      # Specs, decisions, changelog
  .github/workflows/         # CI
```

## First coding deliverable

At M0 implement a repo skeleton with package scripts and CI lint/typecheck/tests; a schema for the supplied card catalog; automated assertions 24 unique definitions and 72 copies; initial phase/state types; README setup and no deployment needed. Do not start multiplayer framework or UI until this passes.

## Code review checkboxes

- Commands idempotent and server authoritative?
- Evidence and accusations obey rulebook?
- Redacted views leak zero hidden data?
- Tests cover the behavior and edges?
- Hono/Cloudflare adapters separated from game rules?
- Guest security and safe logging?
- Release note records any approved decision?
