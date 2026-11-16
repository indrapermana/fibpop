# FIBPOP — Development Plan

## Goal and shipping order

Ship a fun, stable offline-first Flutter card game; add server-authoritative online private rooms; then Quick Start and monetization. Android closed testing first, iOS after app/account readiness, web later. Build **no database or framework abstraction without a direct need**.

## M0 — Workspace & rules freeze

**Work:** repository monorepo scaffold; copy approved English/ID rules; JSON catalog; verify card count and bilingual terminology; record approved rule decisions in `Rules_Clarifications_and_Decisions.md`; `AGENTS.md`; CI lint/typecheck/tests.

**Acceptance:** 72 copies, 24 designs automatically asserted; both rules versions identifiable; no code infers role from card artwork; all unresolved requirements tracked; repository runs bootstrap commands without cloud credentials.

## M1 — Core engine (TypeScript, pure)

**Work:** state types, deterministic RNG/clock injection, secure shuffle adapter, legal moves, draw/shuffle, card actions/reactions, Hearts, Suspicion, Evidence, Cornered/recovery, accusation order, wrong accusations, Secret Finish, victory, event/snapshot projection. At least one fixture per card type and rule transition.

**Acceptance:** repeated sequence produces identical results; impossible illegal moves rejected; no infrastructure imports; win condition correct in edge cases; every source card effect tested.

## M2 — Flutter offline playable

**Work:** Flutter shell, responsive table/hand, two-language localization, tutorial, pure Dart state machine, bots constrained to player views, animations with Flutter or Flame as appropriate, local saved match and settings.

**Acceptance:** 4-player and 8-player matches finish without internet, airplane-mode gameplay supported, save/resume consistent, cross-engine fixtures pass, accessibility labels on card text, 30+ manual offline playtests.

## M3 — Cloudflare API & private game rooms

**Work:** Hono Worker, Zod requests, signed guest auth, DO SQLite game rooms, WebSocket authentication and hibernation, create/join/ready/start, server role/card secrecy, optimistic versioning, idempotency, authoritative turn timers, reconnect snapshot, abandonment/forfeit policy.

**Acceptance:** 4–8 humans can complete private match; clients never get hidden roles/decks; unauthorized commands rejected; repeated commands once only; game recoverable after restart; no loop holds DO awake while idle.

## M4 — Quick Start

**Work:** matchmaking DO, queue join/cancel/expiry, fair room grouping, ready check, timeout/refund of ticket, handling insufficient concurrent players; region/language are soft preferences.

**Acceptance:** no double assignment; abandoned tickets expire; participants routed to a single authoritative room; tests for concurrent joins/cancels.

## M5 — Player safety, reliability, telemetry

**Work:** reconnection, no-show and AFK policy, abuse/reporting for usernames/emotes if introduced, secure token lifecycle, rate limits, replay logs, minimal analytics, errors, admin operations; staging load tests.

**Acceptance:** documented P95 interaction delay target (set after real-world benchmark); crash-free match completion target; 0 critical role/hand leaks; budget and quota alarm strategy; rollback rehearsal.

## M6 — Monetization foundation and beta

**Work:** cosmetic entitlements, optional rewarded ads, post-match interstitial cap, FIBPOP Plus one-time purchase, test purchases and restoration, server-verified receipts, consent/privacy instrumentation. Closed beta first **without monetization**; enable later using feature flags.

**Acceptance:** no purchase changes gameplay odds; rewards idempotent; refunded/revoked purchases corrected; offline is playable without ad SDK; no live-match interstitial; all live data practices disclosed.

## M7 — Android and iOS release

**Work:** brand/legal clearance, original art/sfx licensing, privacy policy and terms, deletion page if account creation, data safety and App Privacy forms, permissions review, age rating, screenshots, store listing, signing, testing track and review notes.

**Acceptance:** complete reviewer access, game operates without forbidden permissions, deletion flow verified, no placeholder text, crash/latency regression green, staged rollout and rollback plan.

## M8 — Web edition (post-mobile validation)

**Work:** responsive Flutter Web UI, Cloudflare Pages, WebSocket origin rules, web guest login, browser reconnect, web-specific payment model assessed separately.

**Acceptance:** browsers can complete both offline and online matches; no role/hand leakage; mobile/web use same server protocol versions.

## Engineering tasks by component

- **Rules:** state machine, event ordering, deterministic tests, replay validator, source catalog loader.
- **Offline AI:** three test difficulties, no omniscient bot knowledge, deterministic bot fixtures.
- **Mobile UX:** cards readability, pass/attack/accuse confirmation, clear Evidence categories, reduced motion toggle.
- **Network:** schema validation, action version checks, at-least-once delivery handling, reconnect, per-player redacted projections.
- **Cloud:** billing account separation awareness, free-tier usage dashboard, hard-cap admission controls, stale room cleanup.
- **Commercial:** purchase integrity, cosmetics, parental/consent targeting decision, legal pages, secure deletion.

## Non-goals for first release

No freeform chat, voice, social network accounts, ranked seasons, real-money gambling, paid random loot boxes, clans, complex leaderboards, or paid competitive cards. Do not require Neon, Redis, Firebase, or Cloud Run for MVP.

## Planning effort

Rough working estimate: **12–20 weeks part-time** for a robust Android + online pilot, depending on rules playtests, assets, bots, testing and store approvals. Not a delivery commitment.

## Exit checklist for each milestone

Provide code, unit tests, integration checks, manual reproduction steps, changelog, open issues, and a short verified summary. Never mark an acceptance condition complete without executing its test.
