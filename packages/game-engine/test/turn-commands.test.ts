import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { executeTurnCommand, validateAttackTarget } from '../src/commands.js';
import {
  endTurnFixtureSchema,
  turnStartFixtureSchema,
} from '../src/golden-fixture.js';
import { beginTurn, spendAction } from '../src/turns.js';

const endTurnFixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-end-turn-recovery.json',
    import.meta.url,
  ),
);
const endTurnFixture = endTurnFixtureSchema.parse(
  JSON.parse(readFileSync(endTurnFixturePath, 'utf8')),
);
const turnStartFixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const turnStartFixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(turnStartFixturePath, 'utf8')),
);

function activeTurn() {
  return beginTurn(turnStartFixture.initialState, {
    next: () => turnStartFixture.randomSequence[0],
  });
}

describe('turn commands', () => {
  it('executes END_TURN and returns the deterministic next state', () => {
    const result = executeTurnCommand(endTurnFixture.initialState, 'player-1', {
      type: 'END_TURN',
      payload: {
        discardCardInstanceIds: endTurnFixture.discardCardInstanceIds,
      },
    });

    expect(result).toEqual({
      ok: true,
      value: endTurnFixture.expectedState,
    });
  });

  it('returns a stable error for an invalid discard choice', () => {
    expect(
      executeTurnCommand(endTurnFixture.initialState, 'player-1', {
        type: 'END_TURN',
        payload: { discardCardInstanceIds: [] },
      }),
    ).toEqual({
      ok: false,
      error: {
        code: 'INVALID_DISCARD_COUNT',
        message: 'Discard exactly 1 card(s) to end the turn',
      },
    });
  });

  it('returns stable failures for malformed, out-of-phase, and wrong-actor commands', () => {
    expect(
      executeTurnCommand(activeTurn(), 'player-1', { type: 'PASS_REACTION' }),
    ).toEqual({
      ok: false,
      error: {
        code: 'INVALID_COMMAND',
        message: 'Turn command payload is invalid.',
      },
    });

    expect(
      executeTurnCommand(turnStartFixture.initialState, 'player-1', {
        type: 'END_TURN',
        payload: { discardCardInstanceIds: [] },
      }),
    ).toMatchObject({
      ok: false,
      error: { code: 'INVALID_PHASE' },
    });

    expect(
      executeTurnCommand(activeTurn(), 'player-2', {
        type: 'SPEND_ACTION',
        payload: { kind: 'action' },
      }),
    ).toMatchObject({
      ok: false,
      error: { code: 'NOT_YOUR_TURN' },
    });
  });

  it('spends a typed action command without mutating its input', () => {
    const state = activeTurn();
    const actorPlayerId = state.currentPlayerId;
    if (!actorPlayerId) {
      throw new Error('Match setup must select a current player');
    }

    const result = executeTurnCommand(state, actorPlayerId, {
      type: 'SPEND_ACTION',
      payload: { kind: 'attack' },
    });

    expect(result.ok).toBe(true);
    if (!result.ok) {
      throw new Error(`Unexpected command error: ${result.error.code}`);
    }

    expect(result.value.actionsRemaining).toBe(1);
    expect(result.value.attacksUsedThisTurn).toBe(1);
    expect(state.actionsRemaining).toBe(2);
    expect(state.attacksUsedThisTurn).toBe(0);
  });

  it('validates another Active attack target without changing state', () => {
    const state = activeTurn();
    const actorPlayerId = state.currentPlayerId;
    if (!actorPlayerId) {
      throw new Error('Match setup must select a current player');
    }
    const targetPlayerId = state.seatOrder.find((id) => id !== actorPlayerId);
    if (!targetPlayerId) {
      throw new Error('Match setup must have another player');
    }
    const originalState = structuredClone(state);

    expect(validateAttackTarget(state, actorPlayerId, targetPlayerId)).toEqual({
      ok: true,
      value: { targetPlayerId },
    });
    expect(state).toEqual(originalState);
  });

  it('rejects self, non-Active, and unavailable attack targets', () => {
    const state = activeTurn();
    const actorPlayerId = state.currentPlayerId;
    if (!actorPlayerId) {
      throw new Error('Match setup must select a current player');
    }
    const otherPlayerId = state.seatOrder.find((id) => id !== actorPlayerId);
    if (!otherPlayerId) {
      throw new Error('Match setup must have another player');
    }

    expect(
      validateAttackTarget(state, actorPlayerId, actorPlayerId),
    ).toMatchObject({ ok: false, error: { code: 'INVALID_TARGET' } });

    const noActions = spendAction(spendAction(state, 'action'), 'action');
    expect(
      validateAttackTarget(noActions, actorPlayerId, otherPlayerId),
    ).toMatchObject({ ok: false, error: { code: 'NO_ACTIONS_REMAIN' } });

    const attackUsed = spendAction(state, 'attack');
    expect(
      validateAttackTarget(attackUsed, actorPlayerId, otherPlayerId),
    ).toMatchObject({ ok: false, error: { code: 'ATTACK_LIMIT' } });
  });
});
