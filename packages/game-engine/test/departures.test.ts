import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  currentAttackResponder,
  respondToAttack,
  startAttack,
} from '../src/attacks.js';
import {
  playStirThePot,
  respondToCardEffectDiscard,
} from '../src/card-effects.js';
import {
  currentAccusationPlayerId,
  expireSecretFinishWindow,
  playLastChance,
  respondToAccusation,
  submitSecretFinishChoice,
} from '../src/cornered.js';
import { handlePlayerDeparture } from '../src/departures.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import { matchStateSchema, type MatchState } from '../src/state.js';
import { beginTurn } from '../src/turns.js';

const fixture = turnStartFixtureSchema.parse(
  JSON.parse(
    readFileSync(
      fileURLToPath(
        new URL(
          '../../../shared/fixtures/m1-turn-start-recycle.json',
          import.meta.url,
        ),
      ),
      'utf8',
    ),
  ),
);
const NOW = Date.UTC(2026, 10, 17);
const forfeit = { kind: 'forfeit', nowMs: NOW + 1 } as const;

function activeState(): MatchState {
  const started = beginTurn(fixture.initialState, { next: () => 0.5 });
  return matchStateSchema.parse({
    ...started,
    drawPile: [],
    discardPile: [],
    players: Object.fromEntries(
      started.seatOrder.map((id) => [
        id,
        {
          ...started.players[id],
          role: id === 'player-4' ? 'impostor' : 'innocent',
          hand: id === 'player-1' ? ['card_01:1', 'card_15:1'] : ['card_09:1'],
        },
      ]),
    ),
  });
}

function corneredState(eligibleAccusers: string[] = []): MatchState {
  const state = activeState();
  const players = { ...state.players };
  players['player-2'] = {
    ...players['player-2'],
    hearts: 1,
    hand: ['card_19:1'],
  };
  for (const id of eligibleAccusers) {
    players[id] = {
      ...players[id],
      evidence: { 'player-2': { clue: true, behavior: true } },
    };
  }
  let attack = startAttack(
    matchStateSchema.parse({ ...state, players }),
    'player-1',
    'player-2',
    'card_01:1',
  );
  while (attack.phase === 'awaiting_reaction') {
    const responder = currentAttackResponder(attack);
    if (!responder) throw new Error('Missing attack responder');
    attack = respondToAttack(attack, responder, { kind: 'pass' }, NOW);
  }
  return attack;
}

describe('disconnects and permanent forfeits', () => {
  it('does not alter state on temporary disconnect, including during a window', () => {
    const state = corneredState(['player-1']);
    expect(
      handlePlayerDeparture(state, 'player-1', { kind: 'disconnect' }),
    ).toEqual(state);
  });

  it('cancels without a winner when the Impostor forfeits during a window', () => {
    const state = corneredState(['player-1']);
    const result = handlePlayerDeparture(state, 'player-4', forfeit);
    expect(result.phase).toBe('cancelled');
    expect(result.winner).toEqual({ kind: 'cancelled_no_winner' });
    expect(result.players['player-4'].status).toBe('eliminated');
    expect(result.pendingCornered).toBeNull();
    expect(result.deadlineUtc).toBeNull();
    expect(result.version).toBe(state.version + 1);
  });

  it('does not declare a win while a Cornered Innocent survives', () => {
    const initial = activeState();
    const players = {
      ...initial.players,
      'player-2': {
        ...initial.players['player-2'],
        status: 'eliminated',
        hearts: 0,
      },
      'player-3': {
        ...initial.players['player-3'],
        status: 'cornered',
        hearts: 0,
      },
      'player-4': {
        ...initial.players['player-4'],
        status: 'cornered',
        hearts: 0,
      },
    };
    const state = matchStateSchema.parse({ ...initial, players });
    const next = handlePlayerDeparture(state, 'player-1', forfeit);
    expect(next.winner).toBeNull();
    expect(next.players['player-3'].status).not.toBe('eliminated');
  });

  it('awards a Cornered Impostor when the final Innocent forfeits', () => {
    const initial = activeState();
    const state = matchStateSchema.parse({
      ...initial,
      players: {
        ...initial.players,
        'player-2': { ...initial.players['player-2'], status: 'eliminated' },
        'player-3': { ...initial.players['player-3'], status: 'eliminated' },
        'player-4': {
          ...initial.players['player-4'],
          status: 'cornered',
          hearts: 0,
        },
      },
    });
    const finished = handlePlayerDeparture(state, 'player-1', forfeit);
    expect(finished.phase).toBe('finished');
    expect(finished.winner).toEqual({ kind: 'winner', playerId: 'player-4' });
    expect(finished.players['player-4']).toMatchObject({
      status: 'cornered',
      hearts: 0,
    });
  });

  it('advances a forfeited turn owner and skips a scheduled Cornered player', () => {
    const state = activeState();
    const prepared = matchStateSchema.parse({
      ...state,
      players: {
        ...state.players,
        'player-2': {
          ...state.players['player-2'],
          status: 'cornered',
          hearts: 0,
        },
      },
    });
    const result = handlePlayerDeparture(prepared, 'player-1', forfeit);
    expect(result.phase).toBe('turn_start');
    expect(result.currentPlayerId).toBe('player-3');
    expect(result.players['player-2']).toMatchObject({
      status: 'active',
      hearts: 1,
    });
    expect(result.version).toBe(prepared.version + 1);
  });

  it('cancels an attack when its target or actor forfeits', () => {
    const attack = startAttack(
      activeState(),
      'player-1',
      'player-2',
      'card_01:1',
    );
    const targetForfeits = handlePlayerDeparture(attack, 'player-2', forfeit);
    expect(targetForfeits.phase).toBe('active_turn');
    expect(targetForfeits.pendingAttack).toBeNull();
    expect(targetForfeits.publicActionHistory).toEqual([]);
    expect(targetForfeits.discardPile).toContain('card_01:1');
    const actorForfeits = handlePlayerDeparture(attack, 'player-1', forfeit);
    expect(actorForfeits.phase).toBe('turn_start');
    expect(actorForfeits.currentPlayerId).toBe('player-2');
    expect(actorForfeits.pendingAttack).toBeNull();
  });

  it('skips a forfeited Step In responder and keeps the attack in progress', () => {
    const attack = startAttack(
      activeState(),
      'player-1',
      'player-2',
      'card_01:1',
    );
    const targetPassed = respondToAttack(
      attack,
      'player-2',
      { kind: 'pass' },
      NOW,
    );
    const next = handlePlayerDeparture(targetPassed, 'player-3', forfeit);
    expect(currentAttackResponder(next)).toBe('player-4');
    expect(next.players['player-3'].status).toBe('eliminated');
    expect(next.version).toBe(targetPassed.version + 1);
  });

  it('skips future Step In responders without canceling the attack', () => {
    const attack = startAttack(
      activeState(),
      'player-1',
      'player-2',
      'card_01:1',
    );
    const withoutFuture = handlePlayerDeparture(attack, 'player-3', forfeit);
    const targetPassed = respondToAttack(
      withoutFuture,
      'player-2',
      { kind: 'pass' },
      NOW + 2,
    );
    expect(currentAttackResponder(targetPassed)).toBe('player-4');
  });

  it('resolves damage when the last Step In responder forfeits', () => {
    const attack = startAttack(
      activeState(),
      'player-1',
      'player-4',
      'card_01:1',
    );
    const targetPassed = respondToAttack(
      attack,
      'player-4',
      { kind: 'pass' },
      NOW,
    );
    const firstPassed = respondToAttack(
      targetPassed,
      'player-1',
      { kind: 'pass' },
      NOW,
    );
    const secondPassed = respondToAttack(
      firstPassed,
      'player-2',
      { kind: 'pass' },
      NOW,
    );
    const result = handlePlayerDeparture(secondPassed, 'player-3', forfeit);
    expect(result.phase).toBe('active_turn');
    expect(result.players['player-4'].hearts).toBe(2);
    expect(result.pendingAttack).toBeNull();
    expect(result.version).toBe(secondPassed.version + 1);
  });

  it('cancels an affected card effect without undoing an already committed discard', () => {
    const state = playStirThePot(
      activeState(),
      'player-1',
      ['player-2', 'player-3'],
      'card_15:1',
    );
    const afterFirst = respondToCardEffectDiscard(
      state,
      'player-2',
      'card_09:1',
    ).state;
    const result = handlePlayerDeparture(afterFirst, 'player-3', forfeit);
    expect(result.phase).toBe('active_turn');
    expect(result.pendingCardEffect).toBeNull();
    expect(result.discardPile).toEqual(['card_15:1', 'card_09:1']);
  });

  it('passes a forfeited current accuser and keeps later eligible offers', () => {
    const original = corneredState(['player-1', 'player-3']);
    const state = matchStateSchema.parse({
      ...original,
      seatOrder: [...original.seatOrder, 'player-5'],
      players: {
        ...original.players,
        'player-5': { ...original.players['player-3'], playerId: 'player-5' },
      },
    });
    const next = handlePlayerDeparture(state, 'player-1', forfeit);
    expect(currentAccusationPlayerId(next)).toBe('player-3');
    expect(next.players['player-1'].status).toBe('eliminated');
    const resolved = respondToAccusation(
      next,
      'player-3',
      { kind: 'accuse' },
      NOW + 2,
    );
    expect(resolved.phase).toBe('turn_start');
    expect(resolved.currentPlayerId).toBe('player-4');
  });

  it('removes forfeited future accusers and cancels the window if its target forfeits', () => {
    const state = corneredState(['player-1', 'player-3']);
    const next = handlePlayerDeparture(state, 'player-3', forfeit);
    expect(next.pendingCornered?.accusationOrderPlayerIds).toEqual([
      'player-1',
    ]);
    const targetForfeits = handlePlayerDeparture(next, 'player-2', forfeit);
    expect(targetForfeits.phase).toBe('active_turn');
    expect(targetForfeits.pendingCornered).toBeNull();
  });

  it('resolves a sealed finish after the last outstanding participant forfeits', () => {
    const state = corneredState();
    const pass = submitSecretFinishChoice(state, 'player-1', 'pass', NOW + 1);
    const finish = submitSecretFinishChoice(
      pass,
      'player-4',
      'finish',
      NOW + 2,
    );
    const result = handlePlayerDeparture(finish, 'player-3', {
      kind: 'forfeit',
      nowMs: NOW + 3,
    });
    expect(result.players['player-2'].status).toBe('eliminated');
    expect(result.phase).toBe('active_turn');
    expect(result.pendingSecretFinish).toBeNull();
  });

  it('advances an eliminated turn owner after Last Chance', () => {
    const state = corneredState();
    const forfeited = handlePlayerDeparture(state, 'player-1', forfeit);
    const window = expireSecretFinishWindow(forfeited, NOW + 10_000);
    const result = playLastChance(window, 'player-2', 'card_19:1');
    expect(result.phase).toBe('turn_start');
    expect(result.currentPlayerId).toBe('player-2');
    expect(result.players['player-2']).toMatchObject({
      status: 'active',
      hearts: 1,
    });
  });

  it('rejects duplicate forfeits, invalid players and unresolved expired windows', () => {
    const state = activeState();
    const result = handlePlayerDeparture(state, 'player-2', forfeit);
    expect(() => handlePlayerDeparture(result, 'player-2', forfeit)).toThrow(
      /cannot forfeit/,
    );
    expect(() => handlePlayerDeparture(state, 'missing', forfeit)).toThrow(
      /belong/,
    );
    const window = corneredState(['player-1']);
    expect(() =>
      handlePlayerDeparture(window, 'player-4', {
        kind: 'forfeit',
        nowMs: NOW + 10_000,
      }),
    ).toThrow(/expired window/);
  });
});
