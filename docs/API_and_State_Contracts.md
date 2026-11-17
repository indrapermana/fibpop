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

The envelope and `expectedVersion` above are an unfinished proposal, not safe to ship unchanged: raw engine versions advance on private submissions. M3 must use privacy-safe synchronization tokens and publication cadence that do not reveal private responses or their number, and bump `protocolVersion` if the wire contract changes.

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

`projectPublicState` includes hand *counts* but never cards held by opponents, private Evidence, raw versions, or sensitive window deadlines. Cornered subphases appear as one public phase. `projectPlayerState` adds only the requesting player's hand, role, Evidence, and private prompt. Elimination and terminal outcomes reveal roles as permitted by the rules. These functions are pure engine views, not authenticated room endpoints.

## Persistence & ordering

Persist each accepted command atomically (state mutation + event record, preferably one transaction). Respond only after commit. All commands serialized by game room Durable Object. Deadline alarms cannot accidentally process a stale phase; include phase/version token. Deduplicate `commandId` for at least match lifetime. Reconnect submits identity and last seen event version; server issues a fresh private snapshot rather than trusting client replay.

The pure engine's `recordTransition` records an authoritative, versioned state delta after an accepted transition; `replayTransitions` applies serialized deltas in order from a trusted initial snapshot without rerunning randomness or clocks. Events are **sensitive private data**, not client events or diagnostic logs. They can contain roles, hands, Evidence, and sealed submissions, including the submitter. M3 must encrypt sensitive replay data before persistence, protect keys and access, and never write plaintext choices or submitter IDs to logs. State deltas alone do not retain ephemeral private results such as inspected cards; the room must deliver or securely retain those results separately when required.

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

After the padded accusation slots complete, open a fixed 10-second sealed Secret Finish window. Active room members submit exactly one authenticated `SECRET_FINISH` (Active Impostor against a Cornered Innocent only) or `PASS_SECRET_FINISH`; nonresponders pass. A Cornered Impostor target receives a pass-only cover window, not a finish opportunity. **Do not broadcast individual choices or submissions.** Resolve only at the deadline, even when all choices arrive early. Finishing costs zero actions and is allowed once per Cornered event. Persist choices securely, then broadcast only victim status and role; `SECRET_FINISH_RESOLVED` and player-facing history must not include actor ID. Invalid FINISH receives a generic rejection. Reconnect must not disclose other choices.

The pure engine stores the padded accusation slot order, sealed submissions, and Last Chance choice in private pending state. Its trusted caller supplies epoch-millisecond timestamps and must invoke the explicit expiry transitions. Each slot and both later windows last 10 seconds; early pass/play responses remain private until the relevant deadline. Never send `pendingSecretFinish.submissions` or raw pending state to clients.

**M3 delivery requirement:** Room snapshots and all messages, errors, acknowledgments, reconnects, and publication timing must preserve the engine's cover and redaction. Do not expose raw phase, raw version, pending choices, eligibility queues, or private transitions; engine projection tests alone cannot establish transport-level secrecy.

If no accusation or Secret Finish eliminates the Cornered target and they hold Last Chance, offer it to that target. Playing it costs no action, discards the card, and restores them to one Heart; passing leaves them Cornered and resumes the interrupted turn. If an incorrect accusation eliminated the interrupted turn owner, advance to the next scheduled turn instead.

**Terminal state:** sole non-eliminated Impostor wins even while Cornered; a surviving Cornered Innocent blocks immediate Impostor victory. Impostor permanent forfeit ends `CANCELLED_NO_WINNER`; disconnection alone does not forfeit.

The engine's `handlePlayerDeparture` distinguishes a state-preserving `disconnect` from an authoritative `forfeit` with an injected timestamp. Only the room decides when permanent forfeiture is justified after reconnect grace. Before applying a forfeit, resolve any expired timed window first; a stale-window forfeit is rejected. Forfeits cancel affected in-progress attacks or card effects, skip forfeited responders, and preserve already committed effects. Pending Secret Finish choices remain private.
