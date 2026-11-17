# FIBPOP — Initial API and State Contracts

This is a **design contract**, not a complete OpenAPI spec. Agent must implement schemas and test them. Any protocol change increments `protocolVersion`. Current proposed `protocolVersion` is **2** (Secret Finish).

## API proposal (Hono)

| Route | Auth | Purpose |
|---|---|---|
| `GET /api/health` | No | Lightweight health/version |
| `POST /api/v1/guest-sessions` | No, rate-limited | Create guest identity/session credential |
| `POST /api/v1/rooms` | Yes | Create private lobby |
| `POST /api/v1/rooms/join` | Yes | Join by invite code |
| `GET /api/v1/rooms/:id` | Yes, authorized | Lobby public view |
| `POST /api/v1/quick-start` | Yes | Queue for public match |
| `DELETE /api/v1/quick-start/:ticket` | Yes | Cancel queue |
| `GET /api/v1/rooms/:id/ws` | Yes + membership | Upgrade to authorized WebSocket |
| `POST /api/v1/account/deletion` | Yes | Request account deletion if accounts offered |

Keep admin APIs separate; never expose a public match-state dump.

## Client → Room command envelope

```json
{
  "protocolVersion": 2,
  "commandId": "unique-idempotency-id",
  "expectedVersion": 31,
  "type": "PLAY_CARD",
  "payload": {
    "cardInstanceId": "instance-123",
    "targetPlayerId": "player-xyz"
  }
}
```

Other candidate commands: `READY`, `START_MATCH`, `END_TURN`, `PLAY_REACTION`, `BASIC_OBSERVE`, `PASS_REACTION`, `PASS_ACCUSATION`, `ACCUSE`, `SECRET_FINISH`, `PASS_SECRET_FINISH`, `PASS_LAST_CHANCE`, `RESUME`. Commands must be validated against exact phases, ownership, ability and limits.

## Server → Client events

`ROOM_SNAPSHOT` (redacted per player), `PLAYER_JOINED`, `MATCH_STARTED`, `TURN_STARTED`, `CARD_PLAYED_PUBLIC`, `REACTION_REQUESTED`, `CORNERED`, `ACCUSATION_OFFERED`, `SECRET_FINISH_WINDOW_OPENED`, `SECRET_FINISH_RESOLVED`, `ACCUSATION_RESOLVED`, `ROLE_REVEALED`, `MATCH_ENDED`, `ERROR`.

Envelope: `{protocolVersion, eventId, matchVersion, type, serverTime, payload}`. Errors include stable codes like `NOT_YOUR_TURN`, `STALE_VERSION`, `INVALID_CARD`, `NOT_ELIGIBLE`, `NOT_ROOM_MEMBER`. Do not reveal secret validation details to the caller.

## State model (server private)

```text
Match: matchId, rulesVersion, catalogVersion, phase, version,
  currentPlayerId, seatOrder, deadlineUtc, randomState,
  deck[instanceIds], discard[instanceIds], roles[playerId],
  hands[playerId], hearts[playerId], suspicion[playerId],
  evidence[investigatorId][suspectId]{clue,behavior},
  activeEffects[], accusationUsed[playerId], pendingCornered?,
  pendingSecretFinish?, winner?,
  eventLog[], processedCommandIds[], createdAt, updatedAt
```

Public projection includes hand *counts* but never card IDs for opponents. Private player projection includes own hand/role/evidence. Hidden identities revealed only on terminal resolution or elimination per rule.

## Persistence & ordering

Persist each accepted command atomically (state mutation + event record, preferably one transaction). Respond only after commit. All commands serialized by game room Durable Object. Deadline alarms cannot accidentally process a stale phase; include phase/version token. Deduplicate `commandId` for at least match lifetime. Reconnect submits identity and last seen event version; server issues a fresh private snapshot rather than trusting client replay.

## Guest security

Use cryptographically secure random IDs and expiring signed credentials; store secrets in Cloudflare secret bindings; hash long-lived reconnect secrets; enforce rate limits. Invite code only locates a room. Separate player membership from guest credential possession; a leaked invite link cannot access another player's hand.

## Cross-engine golden fixture format

```json
{
  "fixtureVersion": 1,
  "rulesVersion": "2.1.0",
  "name": "wrong-accusation-eliminates-both",
  "initialState": "test-data fixture object",
  "command": "accuse suspect",
  "expectedPublicDelta": "two innocent players eliminated",
  "expectedPrivateDelta": "roles revealed only as rules allow"
}
```

Write actual machine-readable fixtures during M0–M1; text examples are intentional placeholders, not implementation-ready JSON fixtures.

## Secret Finish privacy and command handling (protocol v2)

After all eligible 10-second accusation offers pass, open a sealed secret-finish window. Eligible Active room members submit exactly one authenticated `SECRET_FINISH` (Impostor only) or `PASS_SECRET_FINISH` (everyone else). **Do not broadcast who selected either choice, and do not broadcast incoming selections as they happen**. Buffer private submissions until everyone has decided or a short configured timer ends. An Active Impostor can submit FINISH even if it's another player's turn; a Cornered Impostor cannot. Nonresponders pass. Finishing costs zero turn actions and is allowed once per Cornered event, not once per turn. Persist participant choices securely (never include them in per-player or public projections), then commit elimination privately and broadcast only victim status and role. `SECRET_FINISH_RESOLVED` must not include actor ID, and player-facing action history must not expose it. An Invalid Innocent FINISH command receives a generic rejection but must not expose the Impostor's identity. Reconnect during the sealed window must not disclose other choices.

The pure engine stores the accusation offer order and sealed submissions in private pending state. It accepts a trusted epoch-millisecond timestamp from its caller to set/check `deadlineUtc`; each accusation offer lasts 10 seconds, and the Secret Finish window uses the approved 10-second implementation parameter. The engine rejects late submissions and exposes explicit expiry transitions; nonresponses become passes. Never send `pendingSecretFinish.submissions` to clients.

**Projection requirement for M1-13/M3:** The engine skips Secret Finish for an Impostor target, as required by the rules. Exposing that phase transition or its timing directly would reveal the target's hidden role. The online protocol must mask this distinction without offering an actual finish against an Impostor; this privacy behavior is not yet implemented.

If no accusation or Secret Finish eliminates the Cornered target and they hold Last Chance, offer it to that target. Playing it costs no action, discards the card, and restores them to one Heart; passing leaves them Cornered and resumes the interrupted turn. If an incorrect accusation eliminated the interrupted turn owner, advance to the next scheduled turn instead.

**Terminal state:** sole non-eliminated Impostor wins even while Cornered; a surviving Cornered Innocent blocks immediate Impostor victory. Impostor permanent forfeit ends `CANCELLED_NO_WINNER`; disconnection alone does not forfeit.
