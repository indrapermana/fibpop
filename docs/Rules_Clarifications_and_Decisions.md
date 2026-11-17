# FIBPOP — Approved Rules and Decision Register

**Decision date:** 2026-11-16  
**Decision status:** Five gameplay choices explicitly approved by product owner; remaining defaults approved; deterministic technical interpretation documented below.  
**Canonical rulebooks:** `game-rules/Original_Game_Rules_EN.md` and `Original_Game_Rules_ID.md`, rules **2.1**.  
**Card inventory:** **unchanged**, 24 designs / 72 cards. Add 16 **non-action Secret Finish choice cards** (8 FINISH + 8 PASS) as physical-game accessories; they are *not* added to the action deck.

## Explicitly approved choices

| ID | Decision | Locked behavior |
|---|---|---|
| R01 | Cornered recovery = **skip** | At next scheduled turn, if still Cornered, recover to 1 Heart, skip draw and actions, resume next turn. |
| R02 | Impostor finishing = **secret** | After a Cornered player's accusation window, an Active Impostor may finish a Cornered Innocent without exposing their identity. No normal action cost; one opportunity per Cornered event, regardless of whose turn it is. |
| R03 | Accusation timer = **10 seconds per eligible player** | Eligible Active Innocents offered in priority order. Timed-out offer is a pass. |
| R12 | Final Innocent Cornered = **must finish** | No immediate victory; the final Innocent must be permanently eliminated. |
| R-evidence | **Two** Evidence types | One Clue and one Behavior marker held by an Active Innocent against the same Cornered suspect; each player may formally accuse once per match. |

## Approved defaults and implementation interpretations

| ID | Final rule |
|---|---|
| R04 | Playing an Action card or Basic Observe costs 1 action, unless explicitly specified otherwise. Reactions don't; no recursive Reaction chain without explicit card text. |
| R05 | Attack target responds first; if target declines to defend, other eligible Active players may play Step In in clockwise order; at most one successful defense. |
| R06 | Last Chance may activate only after the **entire** accusation window and Secret Finish opportunity resolve without elimination. |
| R07 | Max one Safe Place shield per target; expires upon damage prevention or caster's next turn. |
| R08 | **Superseded:** Reveal & Finish and reveal lifecycle no longer exist. Secret Finish keeps the Impostor hidden. Any roles revealed by accusation or elimination remain revealed. |
| R09 | Behavior Evidence requires an observed, logged successful attack or a publicly visible Noisy manipulation; Base Observe must have qualifying history. |
| R10 | Keep Spotlight unchanged for the prototype and measure its utility. |
| R11 | Check Alibi grants Clue Evidence even if no previous action is recorded; reveal action only when one exists. |
| R13 | If all Innocents are permanently eliminated, the Impostor wins **even when Cornered**. If at least one Innocent is Cornered but not eliminated, no Impostor victory yet. Correct accusation always ends as an Innocent solo victory. A wrong accusation that eliminates the final two Innocents produces an Impostor victory as long as the Impostor remains non-eliminated. |
| R14 | Disconnection alone never eliminates. Use configurable reconnect grace; Innocent forfeiture is permanent elimination. If the Impostor permanently forfeits, cancel the match (no individual winner). Do not confuse a forfeit with a correct accusation. |
| R15 | Offline bot receives only its own private state plus authorized public state, never other hidden roles. |

## Secret Finish procedure and rationale

**Decision consequence:** An Impostor-only anonymous ability is easy to authenticate digitally, but physically it requires a trust-based anonymous submission procedure; cryptographic verification is impossible with only ordinary hidden cards and no moderator. To preserve the physical-card format, add **two choice cards per player** (FINISH and PASS) with identical backs, separate from the 72-card action deck.

1. After zero Hearts is reached, process all eligible accusations in order. A correct accusation immediately ends the match; a wrong accusation immediately eliminates two players and runs a winner check.
2. If there was **no accusation** and target is still Cornered, every Active non-Cornered player submits exactly one choice card face down; shuffle choices anonymously before revealing. Only the Active Impostor is allowed to submit FINISH; all others must PASS. If the Impostor is Cornered, all eligible participants PASS.
3. One FINISH means the Cornered Innocent is eliminated, and only the victim's role is revealed. Zero FINISH means no elimination. More than one FINISH is invalid: retry once, then treat as PASS if still invalid; record fair-play incident.
4. Collect and redistribute anonymous choice cards so every player holds one FINISH and one PASS again; do not trace votes to prior owners. If victim survives, allow Last Chance. Then resume the interrupted turn.
5. **Digital authority:** Client submits authenticated `SECRET_FINISH` or `PASS_SECRET_FINISH` only if eligible. Server privately verifies role and phase, applies one result, and broadcasts only the public result. To avoid revealing who acted via timing, use a **simultaneous sealed-choice window** (suggest 10 seconds total, as an implementation parameter, not the owner's accusation timer), publishing results only when the window closes or all valid choices received; do not broadcast individual responses.

**Physical prototype integrity note:** A dishonest Innocent could submit FINISH anonymously; such a game cannot prove voter eligibility without a moderator or a stronger physical cryptographic prop. This is a *known tabletop limitation*, not a valid online implementation shortcut. If strict physical enforcement is required later, redesign the tabletop procedure separately.

## Deterministic sequence and terminal-state precedence

`resolve attack → defense → damage → Cornered → sequential accusation offers (10 s each) → on accusation, resolve and check winner → if no accusation, sealed Secret Finish vote → victim elimination and winner check → Last Chance (if eligible) → resume turn → next scheduled Cornered recovery/skip`.

- Do not offer Secret Finish if any formal accusation was actually submitted/resolved in that Cornered event; the wrong accusation may already have eliminated the suspect.
- Do not declare Impostor victory just because all remaining Innocents have 0 Hearts. Only permanent elimination counts.
- If the Impostor is the **only non-eliminated** player, it wins whether its Hearts are 0 or above.
- Correct accusation is evaluated as the terminal win immediately, before any finish/victory cycle.
- If the Impostor is permanently forfeited, terminate as cancelled/no winner; there is no unwinnable waiting state.
- Invalid/duplicate/stale actions have no state effect; deadlines resolve once.

## Bilingual terminology audit (2026-11-17)

Reviewed the English and Indonesian 2.1 rulebooks and compared the 24 catalog designs, copy counts, and listed effects. No material gameplay, quantity, or win-condition discrepancy was identified. The following core terms are used consistently:

| English | Indonesian |
|---|---|
| Active | Aktif |
| Cornered | Terpojok |
| Eliminated | Tereliminasi |
| Suspicion | Kecurigaan |
| Evidence | Bukti |
| Clue | Petunjuk |
| Behavior | Perilaku |
| Noisy | Mencolok |
| Secret Finish | Habisi Diam-Diam |

**Localization gap (not a rules discrepancy):** `shared/card_catalog_v1.json` contains only `name_en` and `rules_text_en`; Indonesian card names/effects exist in the Indonesian rulebook but not as machine-readable catalog fields. Address this in M2-02 without changing card IDs, quantities, or effects. Neither rulebook nor the catalog was changed during this audit, and no rules-version bump is needed.

## Engine setup determinism (technical convention)

To keep TypeScript and Dart setup fixtures reproducible, initialization uses an injected random source whose values are finite and in `[0, 1)`. It shuffles the role deck, then the action-card deck with Fisher–Yates, deals four cards from the end of the shuffled action deck to each player in seat order, and selects the starting seat afterward. Card instance IDs use `<design-id>:<1-based-copy-number>`. This specifies engine execution and fixture compatibility only; it does not change the approved tabletop rules or define a production random-number generator.

The selected player enters `turn_start`; that transition draws up to two cards, shuffling the discard pile into the draw pile when needed, then advances to `active_turn`. If both piles are exhausted, draw only the cards still available. At turn end, the player selects exactly enough cards to meet the seven-card hand limit; play then advances clockwise. A Cornered player at their scheduled turn recovers to one Heart and skips that turn. These phase boundaries prevent duplicate turn-start draws and ensure Cornered recovery is applied in seat order.

## Engine action accounting (technical convention)

`active_turn` begins with two actions and zero attacks used. Each accepted normal action spends one action; an attack also increments the per-turn attack count, which cannot exceed one. Reactions do not use this action counter. The engine allows a validated zero-cost action for an explicit rules exception, such as the first eligible Investigation against a player at 3 Suspicion; card-effect logic must verify that exception before using the zero-cost path. Ending a turn resets both counters, and the next `beginTurn` initializes them again. This records the implementation contract for rules 2.1.0; it does not change action limits.

The initial pure-engine command contract supports `END_TURN` (pass to the next seat) and `SPEND_ACTION`, with stable result codes. Attack-target validation is a non-mutating check that requires the current Active actor to have an action and attack available and selects another Active player. Reaction, accusation, and Secret Finish transition logic is implemented in M1-11; no wire protocol behavior is implied here.

`publicActionHistory` records only successful attacks that dealt damage and publicly visible Noisy manipulations, with the acting player and action kind. These are the qualifying logged actions for Behavior Evidence under R09. `suspicionAwardedForDamageThisTurn` is reset at turn boundaries and prevents repeated damage events from awarding more than one Suspicion in a turn; all Suspicion adjustments remain clamped to 0–3.

Investigation implementation preserves Evidence per investigator/suspect pair and keeps inspected-card details in the acting player's private result, not in match events or shared state fields. The first Investigation card played against each target during a turn consumes that target's one opportunity, even if the target is below 3 Suspicion then; a later card is not discounted if Suspicion rises during that turn. The product owner confirmed this interpretation on 2026-11-17. Peek draws one card but skips inspection when the chosen player's hand is empty, as also confirmed on 2026-11-17. Check Alibi reveals no card when the target has no recorded Action card. Hand-inspection prevention from Extra Clue and Misdirection leaves the Evidence effect intact.

Attack implementation follows R05: the target responds first, then eligible Active players (including the attacker) receive Step In in clockwise order after a target pass. A successful defense ends the reaction sequence; if all pass, resolve one damage, consuming Safe Place before reducing Hearts. A Safe Place shield expires when it prevents damage or when its caster reaches their next scheduled turn, including a scheduled Cornered recovery/skip.

Remaining card effects preserve the 2.1.0 card text and add no balance changes. Double Down's target selects a conditional discard when passing; it is discarded only if damage resolves, and a defense leaves the card untouched. Callout exposes the target's latest Action card publicly during the pending attack, if one exists. Corner Them checks its Suspicion and qualifying-history rider when played, so eligible Behavior Evidence is granted even if the attack is later blocked; the product owner confirmed these three interpretations on 2026-11-17.

Stir the Pot is rejected before spending its card or action unless two different other Active players each hold a card; those players choose and discard their own cards in clockwise order after the actor. Catch Your Breath draws up to two and pauses the turn for its owner to discard one before taking another action. Card Swap uses injected randomness to select from the actor's post-play hand and the target's hand. Spotlight returns the public Suspicion values alongside the acting player's private draw.

Cornered resolution offers only Active Innocents with both Evidence types against the target who have not accused before. The attacker is first when eligible; otherwise offers begin clockwise after the attacker. Each offer has a 10-second deadline and an injected timestamp; a timeout is a pass. After all offers pass, a Secret Finish window opens for 10 seconds only when the target is Innocent. It buffers choices from all Active, non-Cornered players; if the Impostor is Cornered while the target is Innocent, the other eligible players still pass through the sealed window because only an Active Impostor can finish. A Cornered Impostor target skips the window. Nonresponses pass, and the actor's identity is not retained in the resolved state or public action history.

An accusation consumes the accuser's one lifetime attempt. A correct accusation ends with an immediate Innocent solo win; a wrong accusation permanently eliminates both Innocents and checks whether the Impostor is now the sole non-eliminated player. The interrupted turn resumes if its owner survives; if the owner was the wrong accuser, the next scheduled turn begins instead. Last Chance is offered only after no accusation and no Secret Finish elimination, and only when the Cornered target holds the card. Playing it is a zero-action Reaction that restores the target to one Heart; passing leaves them Cornered. Secret Finish submissions remain private authoritative state until the window resolves; they must never be broadcast individually.

## Remaining balance questions (NOT missing implementation rules)

Investigation may not reveal enough information to make accusations satisfying; Spotlight utility and 4-player Impostor win rates require playtesting. These do not authorize silently modifying published rules or card quantities.

## Versioning

- `rulesVersion`: **2.1.0**.
- `catalogVersion`: **1.0.0** unchanged; no changes to 72 playing-card definitions/effects.
- `protocolVersion`: bump to **2** before implementation of Secret Finish protocol; protocol proposal is updated.
- All cross-engine tests must cover the exact steps above; edits require an explicit new decision and version bump.
