# FIBPOP — Card Game Rules

**Version 2.1 — Approved prototype rules (2026-11-16)**  
**Players:** 4–8  
**Typical goal:** One winner per game  
**Type:** Hidden-identity, deduction and action card game

## 1. What is FIBPOP?

One player is secretly the **Impostor**. Everyone else is **Innocent**. Players draw cards, investigate, attack, defend and decide whom to trust. Every player has **3 Hearts**.

An Innocent wins **alone** by correctly accusing the Impostor after the suspect reaches zero Hearts. A wrong accusation eliminates **both** the Innocent accuser and the Innocent suspect. The Impostor wins by being the **last surviving player**.

## 2. What is in the game?

- **72 playing cards** (24 different designs; quantities below).
- **8 role cards:** 1 Impostor and 7 Innocent cards. Use only as many Innocent cards as needed.
- **16 Secret Finish choice cards:** 8 FINISH and 8 PASS with identical backs (one pair per player; separate from the 72-card action deck).
- **Hearts:** enough markers to give each player 3.
- **Suspicion markers:** 0–3 for each player.
- **Evidence markers:** two kinds, **Clue** and **Behavior**, identified by both owner and suspect.
- A space for a **draw pile** and **discard pile**. **No board or pawns.**

### Important terms

| Term | Meaning |
|---|---|
| **Active** | Has at least 1 Heart and may take turns. |
| **Cornered** | Has 0 Hearts; cannot take normal actions until rescued or recovered. Not eliminated yet. |
| **Eliminated** | Out of the game; reveal the player's role. |
| **Suspicion** | Public indication of questionable actions; never proves who the Impostor is. |
| **Evidence** | An investigator's markers about a specific suspect. Two different types are needed to accuse. |

## 3. Setup

1. Shuffle **one Impostor** card with enough **Innocent** cards for all players. Deal one role face down to each player. Keep it secret.
2. Shuffle all 72 playing cards. Deal **4 cards** to each player.
3. Give everyone **3 Hearts** and **0 Suspicion**.
4. Choose a starting player at random. Turns move clockwise.

## 4. Your turn

If you are **Active**:

1. **Draw 2 cards** from the draw pile.
2. **Take up to 2 actions.** Usually, playing an Action card costs 1 action. You may make **at most one Attack** per turn.
3. **Discard down to 7 cards** in your hand.
4. Pass to the next player.

A **Reaction** card is played in response to an attack or investigation, not during your own action phase. Only **one defensive Reaction** can stop each attack. If the target declines to defend, another player may use **Step In**.

**Basic Observe:** Instead of playing a card, use 1 action to collect **Behavior Evidence** against a player who has already performed a visible attack or a noisy manipulation. It cannot be earned twice against the same suspect.

If the draw pile runs out, shuffle the discard pile to form a new draw pile.

## 5. Attacking and Hearts

- An Attack targets **any other Active player**. There is no distance rule.
- The target may use one Defense card. If the attack is not blocked, the target loses **1 Heart**.
- When an attack deals damage, its attacker gains **1 Suspicion**, at most once per turn (maximum 3).
- At **0 Hearts**, the target becomes **Cornered**, not immediately eliminated. Stop the turn briefly for an accusation opportunity.
- A Cornered player cannot be attacked again. They can still receive healing.

**Recovery:** If a Cornered player has not been eliminated or healed before their next scheduled turn, they recover to **1 Heart**, skip drawing and actions that turn, and rejoin normal play from the following turn. They cannot take any normal actions while Cornered. A rescued player who becomes Active before their scheduled turn takes that turn normally.

**Cornered resolution:** After an attack reduces a player to 0 Hearts, pause the current turn. Resolve eligible accusations in order, then offer Secret Finish if nobody accuses, then allow `Last Chance` if no finish occurred. Return to the interrupted turn only after this sequence. A player cannot perform a second normal attack during the same turn.

## 6. Evidence and accusations

An Active Innocent may accuse a Cornered player only if they hold **both** of the following against that specific suspect:

- **1 Clue Evidence** — earned with an investigation card.
- **1 Behavior Evidence** — earned from an observed action or qualifying card.

Evidence tells you what a player did; **it does not reveal their role**. Players still need to judge whom to trust. Evidence markers are kept even if a suspect later recovers.

**Who may accuse first?** The player whose attack most recently made the suspect Cornered gets first choice, if eligible. If they pass or lack Evidence, offer the chance clockwise to the other eligible Active players. Each player may accuse **only once per game**. Each eligible Active Innocent receives **10 seconds** to accuse or pass, in order; a timeout means pass. The attacker who caused Cornered is considered first only if eligible; otherwise begin with the next eligible player in clockwise order. If no one accuses, proceed to Secret Finish (Section 7); if there is no finish, the Cornered player stays in play until healed or recovered.

### Accusation results

| Suspect's role | Result |
|---|---|
| **Impostor** | Reveal the role. **The Innocent accuser wins immediately and alone.** |
| **Innocent** | Reveal both roles. **The accuser and suspect are both eliminated.** Play continues. |

The Impostor **cannot make a formal accusation**.

## 7. Secret Finish — how the Impostor eliminates players

The Impostor has one special ability, **Secret Finish**. It allows the Impostor to permanently eliminate a **Cornered Innocent** without publicly revealing their own identity. It is **not a normal action** and costs **0 actions**. It can be attempted **once per Cornered event**, immediately after all eligible players have passed on accusation, even during another player's turn.

**Who may use it?** Only the single Impostor, and only while the Impostor is **Active** (at least 1 Heart and not eliminated). A Cornered Impostor cannot use it. The Cornered target must be an Innocent. The Impostor can pass instead.

**Tabletop procedure (no moderator):**

1. Each **Active, non-Cornered, non-eliminated** player, including the Impostor if Active, secretly chooses their own **FINISH** or **PASS** choice card and places it face down. All eligible players submit one card, so nobody knows who chose what. The Cornered target does not submit a choice.
2. Mix the submitted cards face down so their owners cannot be identified, then reveal the submitted **choices**, *not* the player identities.
3. If exactly **one FINISH** appears, the Cornered Innocent is eliminated; reveal only the victim's role. **Do not reveal who submitted FINISH.** If all choices are PASS, no finish occurs. More than one FINISH is an invalid procedure: cancel the finish, privately remind players that only the Impostor may choose it, and repeat the anonymous choice once. If invalid again, resolve as no finish and record the incident for playtesting.
4. Gather the revealed choice cards and redistribute them as needed so every player again has one FINISH and one PASS card. No one should attempt to trace any chosen card back to its owner. These cards are not part of the 72-card draw pile.
5. If no finish occurred, the Cornered player may play **Last Chance** (if held), then otherwise remains Cornered until healed or their recovery turn.

**Fair-play limitation:** Anonymous tabletop choices cannot cryptographically prove which role chose FINISH. The physical version relies on players following their secret roles honestly; suspicious/invalid votes should be handled by the group's fair-play rules. **The digital game must enforce role eligibility on the authoritative server**, never trusting a client-supplied role or anonymous ballot.

If an accusation correctly identifies the Impostor, the match ends immediately; Secret Finish is not offered. A wrong accusation resolves its eliminations and winner checks before any further action. Secret Finish is not offered for an Impostor target and cannot eliminate the Impostor.

## 8. Suspicion

Suspicion is visible to all, from **0 to 3**.

- Successful damage: attacker gains **+1 Suspicion** (once per turn).
- A card marked **Noisy**: player gains **+1 Suspicion**.
- Card effects may remove Suspicion.
- Suspicion is **never direct proof** of identity. At 3 Suspicion, the first Investigation card played against that player each turn costs **no action**.

## 9. The 72-card deck

There are **24 different card designs** across six categories. **Action** cards are played on your turn; **Reaction** cards are played when their trigger occurs. A card that is used goes to the discard pile.

### Attacks — 18 cards

| Card | Copies | Effect |
|---|---:|---|
| **Pressure!** | 8 | Attack; deal 1 Heart of damage unless blocked. |
| **Double Down** | 4 | Attack; deal 1 damage. If it succeeds, the target discards 1 card. |
| **Callout** | 3 | Attack; deal 1 damage and ask the target to reveal their last played Action card, if any. |
| **Corner Them** | 3 | Attack; deal 1 damage. If the target has 2+ Suspicion, gain Behavior Evidence if they have a recorded qualifying action. |

### Defense — 15 cards

| Card | Copies | Effect |
|---|---:|---|
| **Duck!** | 6 | Reaction: prevent 1 damage to yourself. |
| **Deny It** | 4 | Reaction: prevent 1 damage to yourself and remove 1 of your Suspicion. |
| **Step In** | 3 | Reaction: prevent 1 damage to any target; playable only if that target did not defend. |
| **Countercheck** | 2 | Reaction: prevent 1 damage to yourself; gain Behavior Evidence on the attacker if they have a qualifying public action. |

### Investigation — 14 cards

| Card | Copies | Effect |
|---|---:|---|
| **Look Back** | 5 | Gain Behavior Evidence against a player with a recorded Attack or Noisy action. Otherwise, gain none. |
| **Follow the Trail** | 4 | Gain Clue Evidence on a player; privately inspect 1 random card from their hand, if any. |
| **Peek** | 3 | Privately inspect 1 random card in another player's hand; draw 1 card. |
| **Check Alibi** | 2 | Gain Clue Evidence on a player; ask them to show their most recently played Action card, if any. |

### Manipulation — 10 cards

| Card | Copies | Effect |
|---|---:|---|
| **Point Fingers** | 4 | Give another player 1 Suspicion. **Noisy.** |
| **Clean Slate** | 3 | Remove up to 2 of your Suspicion. **Noisy** (then gain 1 back). |
| **Stir the Pot** | 2 | Two other Active players each discard 1 card. **Noisy.** |
| **Card Swap** | 1 | Swap 1 randomly selected card from your hand with 1 from another player's hand. |

### Recovery — 9 cards

| Card | Copies | Effect |
|---|---:|---|
| **First Aid** | 4 | Restore 1 Heart to yourself or any surviving player, including a Cornered player. |
| **Catch Your Breath** | 3 | Draw 2 cards and discard 1 card. |
| **Last Chance** | 1 | Reaction: if you are Cornered and no accusation was made, recover to 1 Heart immediately. |
| **Patch Up** | 1 | Restore 1 of your Hearts and remove 1 Suspicion. |

### Special — 6 cards

| Card | Copies | Effect |
|---|---:|---|
| **Safe Place** | 2 | Choose yourself or another Active player; the next damage they would take before your next turn is prevented. |
| **Extra Clue** | 2 | Gain Clue Evidence against one player and inspect 1 random card from their hand; they may discard 1 card to prevent the inspection (but not the Evidence). |
| **Spotlight** | 1 | All players show their Suspicion markers; draw 1 card. |
| **Misdirection** | 1 | Reaction to investigation: prevent someone from looking at your hand; Evidence from their card still applies. |

**Total:** 18 + 15 + 14 + 10 + 9 + 6 = **72 cards**. Clue and Behavior Evidence are limited to **one of each per investigator–suspect pair**.

## 10. Winning and special situations

- **Correct accusation:** Innocent accuser wins immediately. Game ends.
- **Wrong accusation:** Innocent accuser and Innocent suspect are both eliminated. Game continues.
- **Impostor sole survivor:** Impostor wins as soon as every Innocent is permanently eliminated, even if the Impostor is Cornered (0 Hearts).
- **No one accuses a Cornered player:** Offer Secret Finish, then Last Chance; if not eliminated, the player may heal or recover on their turn.
- **Several players want to accuse:** Follow the priority order in Section 6; only the first completed accusation counts.
- **A player with 0 Hearts draws a card:** Not allowed until they become Active again.
- **One Innocent and the Impostor remain:** The Innocent being Cornered does not give the Impostor a win; the Innocent must be permanently eliminated.
- **Card effects conflict:** Resolve reactions, damage prevention, Heart changes, Cornered status, accusations and their eliminations, immediate win checks, Secret Finish, Last Chance, and final win checks in that order.
- **If the final Innocents disappear after a wrong accusation:** The sole non-eliminated Impostor wins, including if Cornered.
- **Permanent Impostor forfeit:** Cancel the match with no individual winner. Permanent Innocent forfeit counts as elimination. Temporary disconnect never immediately eliminates anyone.

## 11. Example

Andi, Budi, Citra, Dina and Eko are playing. Budi is secretly the Impostor. Dina has both Evidence markers against Budi. Eko attacks Budi and reduces him to **0 Hearts**. Eko has insufficient Evidence to accuse. The opportunity passes around the table to Dina. Dina accuses Budi, reveals the Impostor card, and **wins alone**.

If Budi had been Innocent, **Dina and Budi would both be eliminated**, and the others would keep playing.

---

*These are complete rules for an initial tabletop playtest, not claims of proven balance. Card amounts and special abilities may change after testing.*
