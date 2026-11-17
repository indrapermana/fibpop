# FIBPOP — Project Pack v1.1

**Product:** FIBPOP (working commercial title; trademark clearance pending)  
**Owner/operator (planned):** PT Indesya Karya Digital  
**Primary launch:** Android, then iOS; web later  
**Languages:** English + Bahasa Indonesia  
**Status:** Gameplay decisions approved (rules 2.1.0); tabletop balance remains unverified.

## Start here (Codex / GitHub Copilot)

1. Read `agent/AGENTS.md` and `agent/START_HERE_PROMPT.md`.
2. Read the immutable *source documents*: `game-rules/Original_Game_Rules_EN.md` (and ID translation), plus `shared/card_catalog_v1.json` (24 designs, 72 copies).
3. Read `docs/Rules_Clarifications_and_Decisions.md` **before implementing**; it identifies ambiguities that must be handled explicitly.
4. Read `docs/Architecture.md`, `docs/Development_Plan.md`, and `docs/API_and_State_Contracts.md`.
5. Implement one milestone at a time; do not silently change gameplay rules or add paid mechanics.

## Pack contents

| File | Purpose |
|---|---|
| `game-rules/Original_Game_Rules_EN.md` | Standalone physical card game rules (English) |
| `game-rules/Original_Game_Rules_ID.md` | Standalone physical card game rules (Indonesian) |
| `shared/card_catalog_v1.json` | Canonical 72-copy/24-design catalog (unchanged) |
| `shared/rules_manifest_v2_1.json` | Machine-readable approved rules and version IDs |
| `docs/Rules_Clarifications_and_Decisions.md` | Missing/ambiguous timing, win and card-effect decisions |
| `docs/Architecture.md` | Locked stack, boundaries, realtime, offline, data and security |
| `docs/Development_Plan.md` | Work phases, implementation tickets, acceptance gates |
| `docs/API_and_State_Contracts.md` | Initial protocol, command validation and persistence shapes |
| `docs/Monetization_and_Business.md` | Revenue strategy, prices, ads, unit economics, operations |
| `docs/Privacy_Terms_and_Store_Release.md` | Publication compliance checklist; legal document outlines |
| `docs/Testing_and_Operations.md` | Rules verification, load testing, budgets, incident handling |
| `agent/AGENTS.md` | Implementation requirements for coding agents |
| `agent/START_HERE_PROMPT.md` | Copy/paste kickoff prompt |

## Locked product decisions

- Card-only gameplay, no main board or pawns. 4–8 players, one Impostor, all others Innocent. Three Hearts each.
- Innocent wins individually by *correctly accusing a Cornered Impostor with Clue + Behavior Evidence*.
- A wrong accusation eliminates both Innocent accuser and Innocent target. Impostor wins by being sole survivor.
- Shared 72-card action deck (24 unique designs), plus 16 physical anonymous Secret Finish choice cards; continuous turns, reactions, Suspicion and Evidence.
- Offline solo with bots initially; online private invite rooms and Quick Start public matchmaking; pass-and-play later.
- Flutter (Dart) UI, selective Flame animations; Flutter Web later.
- Hono + TypeScript on Cloudflare Workers for HTTP; native Durable Objects and hibernating WebSockets for authoritative online rooms; Durable Object SQLite storage.
- Pure TypeScript online rules engine; offline Dart engine validated against shared fixtures; Neon deferred.
- Free-to-play, cosmetic purchases, optional rewarded ads and carefully timed post-match interstitials; no pay-to-win.

## Explicitly not decided

- Original rules have some interactions that require playtest decisions. See the decision log. **Do not treat approved rule decisions as historical user approvals.**
- Visual style, final brand/trademark, collectible cosmetic catalog, ratings and age audience, paid product SKUs, final privacy notices, and per-market pricing require separate sign-off.

## Launch philosophy

1. Make offline gameplay genuinely fun and deterministic.
2. Prove robust secure private multiplayer.
3. Validate Quick Start against actual concurrent-player demand and hosting usage.
4. Publish closed beta without intrusive monetization.
5. Turn on purchases/ads only after consent, compliance, reliable entitlements, and retention validation.

## Local development (M0)

Requirements: Node.js 22+ with npm, Flutter 3.35+ with Dart, and the platform
tooling required by Flutter for your target device. No cloud account or
credentials are needed.

From the repository root:

```sh
npm install
npm run check
```

Run the backend locally (Hono on the Workers runtime):

```sh
npm run dev --workspace @fibpop/backend
```

The local health endpoint is `http://localhost:8787/api/health`. It does not
connect to Cloudflare or create resources.

Run the Flutter app:

```sh
cd apps/mobile
flutter pub get
flutter run
```

Use `flutter analyze` and `flutter test` from `apps/mobile` to check the mobile
app. The app uses Flutter Riverpod 2.6.1 for state management and Flutter
Navigator for routes. App bootstrap and routes live in `lib/app`; screens are
organized by feature in `lib/features`. Offline play is not implemented yet.
Shared cross-engine fixtures live in `shared/fixtures`; the Dart engine and its
fixture runner are planned for M2.
