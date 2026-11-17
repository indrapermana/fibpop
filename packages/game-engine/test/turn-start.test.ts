import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { parseCardCatalog } from '../src/card-catalog.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import { createMatch } from '../src/setup.js';
import { matchStateSchema } from '../src/state.js';
import { beginTurn } from '../src/turns.js';

const catalogPath = fileURLToPath(
  new URL('../../../shared/card_catalog_v1.json', import.meta.url),
);
const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const catalog: unknown = JSON.parse(readFileSync(catalogPath, 'utf8'));
const fixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);

function fixtureRandom() {
  let index = 0;
  return {
    next: () => {
      const value = fixture.randomSequence[index];
      index = (index + 1) % fixture.randomSequence.length;
      return value;
    },
  };
}

describe('turn-start draw', () => {
  it('matches the shared fixture when recycling the discard pile mid-draw', () => {
    expect(beginTurn(fixture.initialState, fixtureRandom())).toEqual(
      fixture.expectedState,
    );
  });

  it('draws two cards and advances to the action phase', () => {
    const state = createMatch({
      matchId: 'turn-start-draw',
      playerIds: ['p1', 'p2', 'p3', 'p4'],
      catalog: parseCardCatalog(catalog),
      random: { next: () => 0.5 },
    });
    const nextState = beginTurn(state, { next: () => 0.5 });

    expect(state.phase).toBe('turn_start');
    expect(nextState.phase).toBe('active_turn');
    expect(nextState.version).toBe(state.version + 1);
    const currentPlayerId = nextState.currentPlayerId;
    if (!currentPlayerId) {
      throw new Error('Match setup must select a current player');
    }

    expect(nextState.players[currentPlayerId].hand).toHaveLength(6);
    expect(nextState.drawPile).toHaveLength(54);
    expect(state.drawPile).toHaveLength(56);
  });

  it('draws only available cards when both piles are empty', () => {
    const exhaustedState = matchStateSchema.parse({
      ...fixture.initialState,
      drawPile: [],
      discardPile: [],
    });
    const nextState = beginTurn(exhaustedState, {
      next: () => {
        throw new Error(
          'Randomness should not be needed when both piles are empty',
        );
      },
    });

    expect(nextState.phase).toBe('active_turn');
    expect(nextState.players['player-1'].hand).toEqual([]);
    expect(nextState.drawPile).toEqual([]);
    expect(nextState.discardPile).toEqual([]);
    expect(exhaustedState.phase).toBe('turn_start');
  });

  it('rejects repeated turn-start draws', () => {
    const activeTurn = beginTurn(fixture.initialState, fixtureRandom());

    expect(() => beginTurn(activeTurn, fixtureRandom())).toThrow(
      /only during the turn_start phase/,
    );
    expect(activeTurn.players['player-1'].hand).toHaveLength(2);
  });
});
