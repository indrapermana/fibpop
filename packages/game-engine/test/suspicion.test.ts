import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import {
  adjustSuspicion,
  hasBehaviorEvidenceQualifyingAction,
  recordNoisyManipulation,
  recordSuccessfulAttackDamage,
} from '../src/suspicion.js';
import { beginTurn, endTurn, spendAction } from '../src/turns.js';

const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const fixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);

function activeTurn() {
  return beginTurn(fixture.initialState, {
    next: () => fixture.randomSequence[0],
  });
}

describe('Suspicion and public action history', () => {
  it('clamps Suspicion changes to the 0–3 range without mutating input', () => {
    const state = fixture.initialState;
    const atMaximum = adjustSuspicion(state, 'player-1', 10);
    const atMinimum = adjustSuspicion(atMaximum, 'player-1', -10);

    expect(atMaximum.players['player-1'].suspicion).toBe(3);
    expect(atMinimum.players['player-1'].suspicion).toBe(0);
    expect(state.players['player-1'].suspicion).toBe(0);
  });

  it('rejects unknown players and non-integer Suspicion changes', () => {
    expect(() =>
      adjustSuspicion(fixture.initialState, 'missing-player', 1),
    ).toThrow(/Unknown player/);
    expect(() =>
      adjustSuspicion(fixture.initialState, 'player-1', 0.5),
    ).toThrow(/must be an integer/);
  });

  it('adds one Suspicion and a qualifying public record for a Noisy action', () => {
    const state = activeTurn();
    const actorPlayerId = state.currentPlayerId;
    if (!actorPlayerId) {
      throw new Error('Match setup must select a current player');
    }

    const afterActionSpend = spendAction(state, 'action');
    const afterNoisyAction = recordNoisyManipulation(
      afterActionSpend,
      actorPlayerId,
    );

    expect(afterNoisyAction.players[actorPlayerId].suspicion).toBe(1);
    expect(afterNoisyAction.publicActionHistory).toEqual([
      { playerId: actorPlayerId, kind: 'noisy_manipulation' },
    ]);
    expect(
      hasBehaviorEvidenceQualifyingAction(afterNoisyAction, actorPlayerId),
    ).toBe(true);
    expect(
      hasBehaviorEvidenceQualifyingAction(afterNoisyAction, 'player-2'),
    ).toBe(false);
  });

  it('records successful damage and awards Suspicion at most once per turn', () => {
    const state = activeTurn();
    const attackerPlayerId = state.currentPlayerId;
    if (!attackerPlayerId) {
      throw new Error('Match setup must select a current player');
    }

    const attackSpent = spendAction(state, 'attack');
    const afterDamage = recordSuccessfulAttackDamage(
      attackSpent,
      attackerPlayerId,
    );

    expect(afterDamage.players[attackerPlayerId].suspicion).toBe(1);
    expect(afterDamage.suspicionAwardedForDamageThisTurn).toBe(true);
    expect(afterDamage.publicActionHistory).toEqual([
      { playerId: attackerPlayerId, kind: 'successful_attack' },
    ]);
    expect(
      hasBehaviorEvidenceQualifyingAction(afterDamage, attackerPlayerId),
    ).toBe(true);
    expect(() =>
      recordSuccessfulAttackDamage(afterDamage, attackerPlayerId),
    ).toThrow(/already recorded this turn/);

    const nextTurn = beginTurn(endTurn(afterDamage, []), {
      next: () => fixture.randomSequence[0],
    });
    expect(nextTurn.suspicionAwardedForDamageThisTurn).toBe(false);
    expect(nextTurn.publicActionHistory).toEqual(
      afterDamage.publicActionHistory,
    );
  });

  it('records successful attack history without exceeding the Suspicion cap', () => {
    const state = activeTurn();
    const attackerPlayerId = state.currentPlayerId;
    if (!attackerPlayerId) {
      throw new Error('Match setup must select a current player');
    }
    const cappedState = {
      ...state,
      players: {
        ...state.players,
        [attackerPlayerId]: {
          ...state.players[attackerPlayerId],
          suspicion: 3,
        },
      },
    };

    const result = recordSuccessfulAttackDamage(
      spendAction(cappedState, 'attack'),
      attackerPlayerId,
    );
    expect(result.players[attackerPlayerId].suspicion).toBe(3);
    expect(result.suspicionAwardedForDamageThisTurn).toBe(true);
  });

  it('requires an attack to be spent before recording successful damage', () => {
    const state = activeTurn();
    const attackerPlayerId = state.currentPlayerId;
    if (!attackerPlayerId) {
      throw new Error('Match setup must select a current player');
    }

    expect(() => recordSuccessfulAttackDamage(state, attackerPlayerId)).toThrow(
      /must follow the current player's attack/,
    );
  });
});
