import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { parseCardCatalog } from '../src/card-catalog.js';
import { matchSetupFixtureSchema } from '../src/golden-fixture.js';
import { createMatch, MAX_PLAYERS, MIN_PLAYERS } from '../src/setup.js';

const catalogPath = fileURLToPath(
  new URL('../../../shared/card_catalog_v1.json', import.meta.url),
);
const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-deterministic-setup.json',
    import.meta.url,
  ),
);
const catalog: unknown = JSON.parse(readFileSync(catalogPath, 'utf8'));
const fixture = matchSetupFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);

function fixtureRandom() {
  let index = 0;
  return {
    next: () => {
      const value = fixture.setup.randomSequence[index];
      index = (index + 1) % fixture.setup.randomSequence.length;
      return value;
    },
  };
}

describe('match setup', () => {
  it('matches the shared deterministic setup fixture', () => {
    const state = createMatch({
      ...fixture.setup,
      catalog: parseCardCatalog(catalog),
      random: fixtureRandom(),
    });

    expect(state).toEqual(fixture.expectedState);
  });

  it('deals one Impostor, three Hearts and four unique cards per player', () => {
    const playerIds = ['p1', 'p2', 'p3', 'p4'];
    const state = createMatch({
      matchId: 'invariant-test',
      playerIds,
      catalog,
      random: { next: () => 0.25 },
    });
    const allDealtCards = playerIds.flatMap(
      (playerId) => state.players[playerId].hand,
    );

    expect(
      Object.values(state.players).filter(
        (player) => player.role === 'impostor',
      ),
    ).toHaveLength(1);
    expect(
      Object.values(state.players).every(
        (player) =>
          player.hearts === 3 &&
          player.suspicion === 0 &&
          player.status === 'active' &&
          player.hand.length === 4,
      ),
    ).toBe(true);
    expect(new Set([...allDealtCards, ...state.drawPile]).size).toBe(72);
    expect(state.drawPile).toHaveLength(56);
    expect(state.phase).toBe('turn_start');
    expect(playerIds).toContain(state.currentPlayerId);
  });

  it('deals the correct number of cards in an eight-player game', () => {
    const playerIds = Array.from(
      { length: MAX_PLAYERS },
      (_, index) => `p${index}`,
    );
    const state = createMatch({
      matchId: 'eight-player-test',
      playerIds,
      catalog,
      random: { next: () => 0.5 },
    });

    expect(
      Object.values(state.players).map((player) => player.hand),
    ).toHaveLength(MAX_PLAYERS);
    expect(state.drawPile).toHaveLength(40);
  });

  it.each([MIN_PLAYERS - 1, MAX_PLAYERS + 1])(
    'rejects a player count of %i',
    (count) => {
      const playerIds = Array.from(
        { length: count },
        (_, index) => `p${index}`,
      );

      expect(() =>
        createMatch({
          matchId: 'invalid-count',
          playerIds,
          catalog,
          random: { next: () => 0.5 },
        }),
      ).toThrow(/4–8 unique player IDs/);
    },
  );

  it('rejects invalid random values instead of silently substituting', () => {
    expect(() =>
      createMatch({
        matchId: 'invalid-rng',
        playerIds: ['p1', 'p2', 'p3', 'p4'],
        catalog,
        random: { next: () => 1 },
      }),
    ).toThrow(/finite value in \[0, 1\)/);
  });
});
