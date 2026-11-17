import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  endTurnFixtureSchema,
  turnStartFixtureSchema,
} from '../src/golden-fixture.js';
import { matchStateSchema } from '../src/state.js';
import { beginTurn, endTurn } from '../src/turns.js';

const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-end-turn-recovery.json',
    import.meta.url,
  ),
);
const fixture = endTurnFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);
const drawFixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const drawFixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(drawFixturePath, 'utf8')),
);

describe('end turn', () => {
  it('matches the fixture for discard, clockwise advance and Cornered recovery', () => {
    const originalState = structuredClone(fixture.initialState);
    const nextState = endTurn(
      fixture.initialState,
      fixture.discardCardInstanceIds,
    );

    expect(nextState).toEqual(fixture.expectedState);
    expect(fixture.initialState).toEqual(originalState);
    expect(fixture.initialState.players['player-3'].status).toBe('cornered');
  });

  it('requires exactly enough owned, unique cards to meet the hand limit', () => {
    expect(() => endTurn(fixture.initialState, [])).toThrow(
      /Discard exactly 1 card/,
    );
    expect(() => endTurn(fixture.initialState, ['not-in-hand'])).toThrow(
      /must be in the current player hand/,
    );

    const nineCardState = matchStateSchema.parse({
      ...fixture.initialState,
      players: {
        ...fixture.initialState.players,
        'player-1': {
          ...fixture.initialState.players['player-1'],
          hand: [...fixture.initialState.players['player-1'].hand, 'p1-card-9'],
        },
      },
    });

    expect(() => endTurn(nineCardState, ['p1-card-8', 'p1-card-8'])).toThrow(
      /must be unique/,
    );
  });

  it('requires an active turn and cannot end the same turn twice', () => {
    const nextTurn = endTurn(
      fixture.initialState,
      fixture.discardCardInstanceIds,
    );

    expect(() => endTurn(nextTurn, [])).toThrow(
      /only during the active_turn phase/,
    );
  });

  it('starts the next active player without requiring a discard at or below limit', () => {
    const activeTurn = beginTurn(drawFixture.initialState, {
      next: () => drawFixture.randomSequence[0],
    });
    const nextTurn = endTurn(activeTurn, []);

    expect(nextTurn.phase).toBe('turn_start');
    expect(nextTurn.currentPlayerId).not.toBe(activeTurn.currentPlayerId);
    expect(nextTurn.discardPile).toEqual(activeTurn.discardPile);
  });
});
