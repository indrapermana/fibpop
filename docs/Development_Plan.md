# FIBPOP — Development Plan

## Goal and shipping order

Ship a fun, stable offline-first Flutter card game; add server-authoritative online private rooms; then Quick Start and monetization. Android closed testing first, iOS after app/account readiness, web later. Build **no database or framework abstraction without a direct need**.

Tasks are ordered within each milestone and use stable IDs for tracking. Check a task only after its deliverable exists and its stated verification has run. The milestone acceptance gate must pass before starting the next milestone. M0 and the completed M1 items below reflect work verified in this repository; a checked item does not imply its entire milestone is complete.

## M0 — Workspace & rules freeze

**Acceptance:** 72 copies, 24 designs automatically asserted; rules versions identifiable; unresolved requirements tracked; local checks run without cloud credentials. No gameplay is inferred from card artwork.

- [x] **M0-01 — Scaffold the monorepo.** Add mobile, backend, pure game-engine, shared, documentation, and CI locations without introducing an external service dependency.
- [x] **M0-02 — Validate the source card catalog.** Parse the supplied catalog and automatically assert 24 unique designs and exactly 72 total copies.
- [x] **M0-03 — Define base engine and fixture types.** Add versioned match/player/phase types, validation schemas, and a shared fixture format with a sample state.
- [x] **M0-04 — Add development commands and CI.** Provide format, lint, typecheck, and test commands; run TypeScript and Flutter checks in GitHub Actions.
- [x] **M0-05 — Add local app/backend instructions.** Scaffold a Flutter Android/iOS/web shell and a local-only Hono Worker health endpoint; do not deploy or configure accounts.
- [x] **M0-06 — Preserve the approved rules baseline.** Keep rules 2.1 and catalog 1.0.0 unchanged; retain the decision register and its balance questions.
- [x] **M0-07 — Confirm version labels.** Verify the English and Indonesian rulebooks identify version 2.1 and the rules manifest identifies 2.1.0.
- [x] **M0-08 — Audit bilingual terminology.** Review the English/Indonesian rules and card terminology for consistency; record discrepancies without changing gameplay decisions. Audit result is recorded in [Rules_Clarifications_and_Decisions.md](./Rules_Clarifications_and_Decisions.md); the catalog localization gap remains for M2-02.

## M1 — Core engine (pure TypeScript)

**Acceptance:** deterministic fixtures pass; illegal transitions are rejected; engine has no infrastructure imports; terminal outcomes match rules 2.1.0; every card design and key transition has focused coverage.

- [x] **M1-01 — Establish typed match state and random injection.** Use explicit rules/catalog versions and an injected `[0, 1)` random source; keep infrastructure-specific secure RNG outside the pure package.
- [x] **M1-02 — Initialize a match.** Validate 4–8 unique players and catalog version; shuffle one Impostor role and the action deck; deal four unique card instances per player; select the starting seat. Verify the complete deterministic result in a shared fixture.
- [x] **M1-03 — Resolve turn-start draws.** Draw up to two cards, reshuffle discard into draw when required, advance to the active phase once, and cover exhausted piles with fixtures/tests.
- [x] **M1-04 — End a turn.** Validate exact discards to the seven-card hand limit, advance clockwise past eliminated players, recover a Cornered player to one Heart while skipping their scheduled turn, and enter the next `turn_start`.
- [x] **M1-05 — Track turn resources.** Represent the two-action allowance and one-attack-per-turn limit; define when actions are spent and reject excess or out-of-phase actions.
- [x] **M1-06 — Implement basic turn commands.** Add typed `END_TURN` and `SPEND_ACTION` commands with stable results, and non-mutating Active attack-target validation. `END_TURN` passes to the next seat; reaction/accusation/Secret Finish window passes remain deferred to M1-11.
- [x] **M1-07 — Implement Suspicion and public action history.** Enforce the 0–3 range, noisy-card changes, successful-damage gain once per turn, removal effects, and the qualifying public-action record used by Behavior Evidence.
- [x] **M1-08 — Implement Evidence and investigations.** Support one Clue and one Behavior marker per investigator/suspect pair; implement Basic Observe, Look Back, Follow the Trail, Peek, Check Alibi, Extra Clue, inspection defenses, and the 3-Suspicion free-investigation default. Inspection responses resolve atomically; reaction-window orchestration remains in M1-11.
- [x] **M1-09 — Implement attacks and reactions.** Resolve attack target, target defense, optional clockwise Step In, at most one successful defense, damage, Countercheck Evidence, Safe Place, and post-damage Cornered entry in the locked order.
- [x] **M1-10 — Implement remaining card effects.** Implement attack-card riders (Double Down, Callout, Corner Them) plus the remaining manipulation, recovery, and special cards; preserve exact card text, action cost, noisy status, target eligibility, and reaction timing. Last Chance is implemented with its Cornered window in M1-11.
- [x] **M1-11 — Implement Cornered resolution.** Enforce accusation eligibility/order and one accusation per player; resolve wrong/correct accusations, the timed offer sequence, Secret Finish eligibility/window, Last Chance, and resume the interrupted turn. Verified with focused tests and `npm run check`.
- [x] **M1-12 — Implement terminal outcomes and forfeits.** Cover Innocent solo wins, Impostor sole-survivor wins including Cornered status, final Innocent handling, cancellation on Impostor forfeit, and no elimination on disconnect alone. Verified with focused tests and `npm run check`.
- [x] **M1-13 — Add replayable events and safe projections.** Produce deterministic state transitions and public/private player views; prove that hidden roles, hands, deck order, and private Evidence are not exposed. Engine replay and projection tests pass; encrypted storage and transport-level privacy remain M3 responsibilities.
- [x] **M1-14 — Complete engine fixture coverage.** Add shared golden fixtures for every card design, major rule transition, illegal edge, and win/forfeit case; verify replay consistency.
- [x] **M1-15 — Verify engine boundaries.** Run focused tests, lint, and typecheck; confirm the package imports no Hono, Cloudflare, database, or UI modules.

**M1 verification:** `npx vitest run packages/game-engine/test` passed 162 tests; `npm run check` passed formatting, lint, typecheck, and 163 tests. A TypeScript AST audit of all 21 engine source files found only in-package imports and Zod, with no dynamic imports or `require` calls. Test-only Node helpers are outside the production source boundary. Dart fixture parity remains M2 work; encrypted replay storage and transport-level secrecy remain M3 work.

## M2 — Flutter offline playable

**Depends on:** M1 engine contracts and fixture format.

**Acceptance:** 4-player and 8-player matches complete without internet; save/resume is consistent; Dart engine passes shared fixtures; card content is readable and accessible; complete at least 30 documented manual playtests.

- [x] **M2-01 — Establish Flutter app structure.** Select and pin one state-management approach; create navigation and feature folders without adding online dependencies. Flutter Riverpod 2.6.1 and built-in Navigator are in place; format, analysis, and widget tests pass.
- [x] **M2-02 — Localize the experience.** Add English and Bahasa Indonesia UI strings, card names/text, rules help, and language selection; keep gameplay data separate from translated presentation. Device-language fallback and in-session selection are tested; saving the selection remains M2-06.
- [ ] **M2-03 — Build the playable table UI.** Implement player seats, Hearts, Suspicion, Evidence, draw/discard piles, hand, legal action prompts, confirmations, and Cornered/accusation screens. The user chose to begin M2-04 first so this UI can use real engine behavior.
- [ ] **M2-04 — Port the offline rules engine to Dart.** Keep it pure Dart, inject randomness/clock, and match TypeScript behavior using the shared fixtures. In progress: deterministic setup, turn start/end, action limits, Suspicion, public-action history, Evidence, investigations, attack/reaction handling including attack-card riders and Safe Place, all current action-card effects, Cornered resolution, terminal outcomes, forfeits, player/public projections, and authoritative transition replay have focused/shared-scenario tests. Full scenario parity remains.
- [ ] **M2-05 — Add constrained offline bots.** Implement initial bot behavior using only that bot’s private state and authorized public state; test against hidden-state leakage.
- [ ] **M2-06 — Add local match persistence and settings.** Save/resume matches, language, accessibility, and audio preferences; verify interrupted games restore consistently.
- [ ] **M2-07 — Add tutorial and accessibility.** Explain turn flow and evidence; add card semantics, scalable text, reduced motion, and keyboard/screen-reader support where applicable.
- [ ] **M2-08 — Verify offline play.** Add widget/integration tests for setup and full matches at 4 and 8 players; execute and document the 30+ playtests.

## M3 — Cloudflare API & private game rooms

**Depends on:** M1 rules and projections; M2 client protocol needs may be developed alongside the mobile UI.

**Acceptance:** 4–8 humans complete a private match; no hidden role/hand leaks; invalid or repeated commands are rejected/idempotent; rooms recover after restart; idle WebSockets do not keep a loop awake.

- [ ] **M3-01 — Implement the Hono Worker shell.** Add typed/Zod-validated HTTP routes, health/version reporting, and local Wrangler development.
- [ ] **M3-02 — Implement guest sessions.** Issue signed, expiring credentials with secure randomness; validate authorization and rate-limit session creation/join attempts.
- [ ] **M3-03 — Implement GameRoom Durable Object storage.** Persist match state, event records, snapshots, deadlines, membership, and processed command IDs with SQLite-backed DO storage.
- [ ] **M3-04 — Implement private-room lifecycle.** Create/join lobby, enforce 4–8 seats, ready/start, deal roles/cards on the server, and reject unauthorized state transitions.
- [ ] **M3-05 — Implement authenticated hibernating WebSockets.** Authenticate membership before upgrade; use native DO hibernation APIs and minimal safe socket attachments.
- [ ] **M3-06 — Make commands authoritative and idempotent.** Validate actor, phase, ownership, expected version, and command ID; serialize and commit mutation/events before acknowledging.
- [ ] **M3-07 — Implement per-player projections.** Return public state plus only the requesting player’s role, hand, Evidence, and prompts; test every event/snapshot for leakage.
- [ ] **M3-08 — Add deadlines and reconnect.** Use DO alarms with phase/version guards; reauthenticate reconnects and send a fresh redacted snapshot; implement disconnect/grace/forfeit behavior.
- [ ] **M3-09 — Verify private-room integration.** Test local full matches, unauthorized commands, duplicate/stale commands, restart recovery, WebSocket hibernation, and role/hand secrecy.

## M4 — Quick Start

**Depends on:** M3 room start/join and membership contracts.

**Acceptance:** no double assignment; expired/abandoned tickets clear; ready participants reach one authoritative room; concurrent join/cancel scenarios pass.

- [ ] **M4-01 — Define queue tickets.** Specify ticket identity, TTL, status transitions, cancellation semantics, and minimal stored preference data.
- [ ] **M4-02 — Implement matchmaking Durable Object.** Add join/cancel/expiry operations and atomic queue updates; do not assign one ticket to multiple rooms.
- [ ] **M4-03 — Group eligible players.** Form 4–8 player rooms; treat region and language as soft preferences and handle insufficient concurrency without false matches.
- [ ] **M4-04 — Add ready check and assignment.** Reserve a room, obtain ready responses, expire no-shows, and requeue or release remaining players according to a documented policy.
- [ ] **M4-05 — Route clients to the room.** Return room connection details without exposing credentials or hidden match data; validate membership at the GameRoom.
- [ ] **M4-06 — Test contention and cleanup.** Cover concurrent joins/cancels, expiry, no-shows, duplicate requests, queue recovery, and admission caps.

## M5 — Player safety, reliability, telemetry

**Depends on:** M3 online rooms; M4 queue before Quick Start operational readiness.

**Acceptance:** documented latency/reliability targets, no critical secrecy leaks, budget/quota alerts, safe token lifecycle, and a rehearsed rollback path.

- [ ] **M5-01 — Finalize player safety policies.** Specify no-show/AFK, reconnect grace, forfeits, reporting, and username/emote moderation only if those features exist.
- [ ] **M5-02 — Harden identity and abuse controls.** Rotate/revoke credentials, rate-limit sensitive routes/commands, protect invite locators, and avoid logging credentials.
- [ ] **M5-03 — Define privacy-safe telemetry.** Record minimal operational metrics and match outcomes; exclude roles, hands, Evidence, invite codes, and personal data not needed for operations.
- [ ] **M5-04 — Improve observability and support.** Add structured errors, health signals, privacy-safe replay/diagnostic access, and documented admin procedures.
- [ ] **M5-05 — Set service objectives and budgets.** Measure real usage before setting P95 interaction/crash-free targets; define quota, spending, and admission alerts.
- [ ] **M5-06 — Load and failure test.** Exercise reconnects, hibernation, alarms, spikes, storage failures, and queue contention in staging.
- [ ] **M5-07 — Rehearse incident response and rollback.** Verify recovery steps, data retention, rollback, and communications for a simulated incident.

## M6 — Monetization foundation and beta

**Depends on:** reliable offline/online play and baseline safety/privacy; run closed beta without monetization first.

**Acceptance:** purchases never affect odds; entitlements/rewards are idempotent; refunds/revocations reconcile; offline play works without ad SDK; no live-match interstitials; disclosures match actual data practices.

- [ ] **M6-01 — Run a no-monetization closed beta.** Validate onboarding, retention, reliability, and safety before enabling ad/purchase SDKs.
- [ ] **M6-02 — Define cosmetic inventory and entitlements.** Keep cosmetics visual-only; define ownership, restore, expiry, and server authority without gameplay advantage.
- [ ] **M6-03 — Implement purchase verification.** Validate platform receipts server-side, persist entitlement changes safely, and support restore/refund/revocation reconciliation.
- [ ] **M6-04 — Implement FIBPOP Plus.** Add the approved one-time product only after platform/store readiness and confirm it grants no competitive advantage.
- [ ] **M6-05 — Implement optional rewarded ads.** Gate rewards behind consent/availability; make reward issuance idempotent and keep offline gameplay independent from the SDK.
- [ ] **M6-06 — Apply ad placement limits.** Enforce post-match interstitial caps and prohibit interruptions during live matches.
- [ ] **M6-07 — Add consent and monetization tests.** Verify feature flags, disclosures, consent state, receipt failures, duplicate callbacks, refunds, and offline behavior.

## M7 — Android and iOS release

**Depends on:** release candidate for M2/M3, safety/privacy readiness, and separately approved commercial/legal decisions.

**Acceptance:** complete reviewer access, compliant data/store declarations, tested deletion flow when accounts exist, no placeholders, green regression, staged rollout and rollback plan.

- [ ] **M7-01 — Complete brand and content clearance.** Approve title/trademark, original art/audio licenses, age audience, ratings, and store-safe content.
- [ ] **M7-02 — Complete legal and privacy materials.** Finalize privacy notice/terms and data disclosures; provide deletion flow if accounts are offered.
- [ ] **M7-03 — Audit app permissions and data handling.** Remove unnecessary permissions/SDKs; verify Android Data Safety and Apple App Privacy declarations against actual behavior.
- [ ] **M7-04 — Prepare release builds.** Configure signing securely, versioning, build reproducibility, crash reporting, and environment separation.
- [ ] **M7-05 — Prepare store listings.** Produce localized descriptions/screenshots, ratings, support links, reviewer instructions, and test credentials that reveal no real player data.
- [ ] **M7-06 — Run release candidate regression.** Test offline/online completion, reconnect, accessibility, purchases if enabled, privacy/deletion, and supported devices.
- [ ] **M7-07 — Submit and manage staged rollout.** Use closed testing first, monitor health/budgets, define rollout thresholds, and rehearse rollback.

## M8 — Web edition (post-mobile validation)

**Depends on:** successful mobile validation and stable shared protocol.

**Acceptance:** browsers complete offline and online matches, preserve secrecy, reconnect correctly, and use the same rules/protocol versions as mobile.

- [ ] **M8-01 — Validate Flutter Web readiness.** Audit plugin/browser compatibility, responsive layouts, performance, and web-specific accessibility.
- [ ] **M8-02 — Implement responsive web UI.** Adapt table, hand, lobby, and dialogs for desktop/mobile browsers without changing game rules.
- [ ] **M8-03 — Host the web client.** Configure Cloudflare Pages environments, asset caching, headers, and safe deployment/rollback.
- [ ] **M8-04 — Secure browser networking.** Configure WebSocket origin checks, guest-session handling, reconnect, and browser storage limits.
- [ ] **M8-05 — Assess web monetization separately.** Review applicable web store/payment policies before enabling any purchase flow.
- [ ] **M8-06 — Verify cross-platform parity.** Run shared fixtures and full browser matches; check protocol versions and all secrecy boundaries.

## Non-goals for first release

No freeform chat, voice, social network accounts, ranked seasons, real-money gambling, paid random loot boxes, clans, complex leaderboards, or paid competitive cards. Do not require Neon, Redis, Firebase, or Cloud Run for MVP.

## Planning effort

Rough working estimate: **12–20 weeks part-time** for a robust Android + online pilot, depending on rules playtests, assets, bots, testing and store approvals. This is not a delivery commitment.

## Exit checklist for each milestone

- [ ] Code and focused tests are complete; run the smallest relevant test set and the milestone checks.
- [ ] Integration checks and manual reproduction steps are recorded.
- [ ] Changes and open decisions are summarized; no unchecked acceptance criterion is claimed complete.
- [ ] Record the exact commands/results and verified milestone status before advancing.
