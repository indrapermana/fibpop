# Testing and Operations

## Mandatory engine test classes

- Catalog 72 copies, 24 unique IDs, category counts consistent in every client.
- Heart transitions (3→2→1→0, shield, heal from Cornered), action caps, draw/discard, empty deck reshuffle.
- Evidence types each capped to one per investigator–suspect pair; only valid public history creates Behavior evidence.
- Correct accusation wins once, wrong accusation eliminates two, expired/duplicate accusation fails, wrong phase fails.
- Secret Finish works only for an Active Impostor with a Cornered Innocent, private submission, sealed result, and no public actor identifier.
- Fair event ordering: defense → damage → cornered → accusation window → result/victory; verify room state version and deduplication.
- Race tests: simultaneous cards, reaction timeouts, reconnect during accusations, game restart during partial action.
- Hidden-info security: assert every player-specific snapshot excludes other hands, roles and deck order, even on errors and reconnect.

## Quality gates

- Every card has at least one positive and one illegal/edge-case test.
- Both Dart and TypeScript engines execute identical golden fixtures.
- Offline 4-, 6-, and 8-player full-match tests against bots; online full-match tests at 4–8 players.
- Android low-end device, network drop, clock drift, screen resize, reduced motion, English/Indonesian overflow.
- Fuzz legal/illegal commands and verify no negative hearts, duplicate hands, double win, or illegal state.

## Release instrumentation

Record coarse: match created/started/completed, duration, role winner, reason for termination, abandon/reconnect, card category counts, queue wait, errors. Never log full hidden game state, raw player credentials, opponent hands or fine-grained personal data unless absolutely necessary and protected.

## Cloudflare launch controls

- Staging and production bindings/config, secrets never committed.
- Use hibernating WebSockets and alarm-based deadlines. No permanent polling/intervals in Durable Objects.
- Limit concurrent room creation and Quick Start queue admission near capacity; fail gracefully rather than overrun free quotas.
- Daily usage dashboards: Workers requests, DO requests/duration, SQLite writes/reads/stored data, errors. Define alerts and budget ceilings before large launch.
- Keep migration/rollback procedures and schema version tags. Rehearse recovery after DO restart and no-memory state.

## Playtest dashboard

Track average turns per player, attacks, defensive responses, Cornered cycles, Evidence attained, accusation attempts, false accusations, Impostor win %, completion times, user-reported perceived fairness and difficulty. No claim of balance until observed testing confirms it.

## Incident runbook

Symptoms: runaway request usage, reconnect storm, stuck room, duplicate score/reward, information leak. Response: stop public matchmaking admission, preserve minimal redacted logs, rollback Worker version if safe, disable monetization via flags, evaluate state migrations, notify affected players where warranted. Recover DO state from persisted snapshots/events and reauthorize all websocket clients.

## Required approved-rules regression fixtures (2.1.0)

1. Cornered next scheduled turn -> 1 Heart; no draw or action; following turn normal.
2. Accusation passes: 10 s **per eligible Active Innocent**, attacker-first priority then clockwise; timeout pass.
3. Evidence: both Clue and Behavior linked to suspect required; duplicate markers forbidden.
4. Secret Finish on other player's turn by Active Impostor -> legal; identity not exposed to spectators, other players, plaintext logs, or public snapshot. Sensitive replay payloads require encryption and controlled access before persistence.
5. Innocent SECRET_FINISH, Impostor at zero Hearts, and finish of non-Cornered target -> rejected without mutation.
6. Sealed submissions: spectators cannot infer sender by timing; duplicates/reconnect do not change outcome.
7. Last Innocent at 0 Hearts remains non-eliminated -> no Impostor win.
8. Last Innocent eliminated by Secret Finish -> Impostor win, even if a different rule places Impostor at zero Hearts after resolution (check terminal invariant).
9. Wrong accusation eliminates last two Innocents and only Impostor remains at 0 Hearts -> Impostor win immediately.
10. Correct accusation -> Innocent solo victory; no subsequent finish offered.
11. Permanent Impostor forfeit -> CANCELLED_NO_WINNER; temporary disconnect -> no automatic elimination.
12. Test fixtures execute identically against offline Dart and online TypeScript for identical legal action sequence and RNG seed.
