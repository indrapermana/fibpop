import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  currentCardEffectResponder,
  playCardSwap,
  playCatchYourBreath,
  playCleanSlate,
  playFirstAid,
  playPatchUp,
  playPointFingers,
  playSpotlight,
  playStirThePot,
  respondToCardEffectDiscard,
} from '../src/card-effects.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import { matchStateSchema, type MatchState } from '../src/state.js';
import { beginTurn } from '../src/turns.js';

const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const fixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);

function activeState(
  hands: Record<string, string[]> = {},
  hearts: Record<string, number> = {},
  suspicion: Record<string, number> = {},
): MatchState {
  const started = beginTurn(fixture.initialState, {
    next: () => fixture.randomSequence[0],
  });
  const players = Object.fromEntries(
    started.seatOrder.map((playerId) => [
      playerId,
      {
        ...started.players[playerId],
        hand: hands[playerId] ?? [],
        hearts: hearts[playerId] ?? started.players[playerId].hearts,
        suspicion: suspicion[playerId] ?? 0,
      },
    ]),
  );

  return matchStateSchema.parse({
    ...started,
    drawPile: [],
    discardPile: [],
    players,
  });
}

function sequenceRandom(values: number[]) {
  let index = 0;
  return {
    next: () => values[index++] ?? 0,
  };
}

describe('remaining card effects', () => {
  it('applies Point Fingers to its target and records the noisy play', () => {
    const state = activeState(
      { 'player-1': ['card_13:1'] },
      {},
      { 'player-1': 2, 'player-2': 2 },
    );
    const nextState = playPointFingers(
      state,
      'player-1',
      'player-2',
      'card_13:1',
    );

    expect(nextState.players['player-1'].suspicion).toBe(3);
    expect(nextState.players['player-2'].suspicion).toBe(3);
    expect(nextState.publicActionHistory).toEqual([
      { playerId: 'player-1', kind: 'noisy_manipulation' },
    ]);
    expect(nextState.discardPile).toEqual(['card_13:1']);
    expect(() =>
      playPointFingers(state, 'player-1', 'player-1', 'card_13:1'),
    ).toThrow(/another surviving player/);
    expect(state.actionsRemaining).toBe(2);
    expect(state.players['player-1'].hand).toEqual(['card_13:1']);
  });

  it('removes up to two Suspicion before Clean Slate adds its noisy point', () => {
    const nextState = playCleanSlate(
      activeState({ 'player-1': ['card_14:1'] }, {}, { 'player-1': 3 }),
      'player-1',
      'card_14:1',
    );

    expect(nextState.players['player-1'].suspicion).toBe(2);
    expect(nextState.publicActionHistory).toEqual([
      { playerId: 'player-1', kind: 'noisy_manipulation' },
    ]);
  });

  it('rejects Stir the Pot without two valid holders before spending its cost', () => {
    const state = activeState(
      {
        'player-1': ['card_15:1'],
        'player-2': ['card_09:1'],
      },
      {},
    );
    const original = structuredClone(state);

    expect(() =>
      playStirThePot(state, 'player-1', ['player-2', 'player-3'], 'card_15:1'),
    ).toThrow(/two different other Active players with cards/);
    expect(state).toEqual(original);
  });

  it('makes Stir the Pot targets discard in clockwise order', () => {
    const state = activeState({
      'player-1': ['card_15:1'],
      'player-2': ['card_09:1'],
      'player-4': ['card_10:1'],
    });
    const pending = playStirThePot(
      state,
      'player-1',
      ['player-4', 'player-2'],
      'card_15:1',
    );

    expect(pending.phase).toBe('awaiting_card_effect');
    expect(pending.actionsRemaining).toBe(1);
    expect(pending.players['player-1'].suspicion).toBe(1);
    expect(currentCardEffectResponder(pending)).toBe('player-2');
    expect(() =>
      respondToCardEffectDiscard(pending, 'player-4', 'card_10:1'),
    ).toThrow(/current card-effect responder/);

    const firstDiscard = respondToCardEffectDiscard(
      pending,
      'player-2',
      'card_09:1',
    );
    expect(firstDiscard.nextResponderPlayerId).toBe('player-4');
    const completed = respondToCardEffectDiscard(
      firstDiscard.state,
      'player-4',
      'card_10:1',
    );

    expect(completed.state.phase).toBe('active_turn');
    expect(completed.state.pendingCardEffect).toBeNull();
    expect(completed.state.discardPile).toEqual([
      'card_15:1',
      'card_09:1',
      'card_10:1',
    ]);
    expect(completed.nextResponderPlayerId).toBeNull();
    expect(completed.state.publicActionHistory).toEqual([
      { playerId: 'player-1', kind: 'noisy_manipulation' },
    ]);
  });

  it('swaps randomly selected post-play hand cards and returns a private result', () => {
    const outcome = playCardSwap(
      activeState({
        'player-1': ['card_16:1', 'card_09:1', 'card_10:1'],
        'player-2': ['card_11:1', 'card_12:1'],
      }),
      'player-1',
      'player-2',
      'card_16:1',
      sequenceRandom([0, 0.99]),
    );

    expect(outcome.state.players['player-1'].hand).toEqual([
      'card_10:1',
      'card_12:1',
    ]);
    expect(outcome.state.players['player-2'].hand).toEqual([
      'card_11:1',
      'card_09:1',
    ]);
    expect(outcome.privateResult).toEqual({
      givenToTargetCardInstanceId: 'card_09:1',
      receivedCardInstanceId: 'card_12:1',
    });
    expect(outcome.state.discardPile).toEqual(['card_16:1']);
  });

  it('restores a Cornered player with First Aid and caps Hearts at three', () => {
    const state = matchStateSchema.parse({
      ...activeState(
        {
          'player-1': ['card_17:1'],
        },
        { 'player-2': 0 },
      ),
      players: {
        ...activeState().players,
        'player-1': {
          ...activeState().players['player-1'],
          hand: ['card_17:1'],
        },
        'player-2': {
          ...activeState().players['player-2'],
          status: 'cornered',
          hearts: 0,
        },
      },
    });
    const healed = playFirstAid(state, 'player-1', 'player-2', 'card_17:1');

    expect(healed.players['player-2'].status).toBe('active');
    expect(healed.players['player-2'].hearts).toBe(1);
    expect(healed.discardPile).toEqual(['card_17:1']);
  });

  it('draws two cards for Catch Your Breath and waits for its discard', () => {
    const started = matchStateSchema.parse({
      ...activeState({ 'player-1': ['card_18:1'] }),
      drawPile: ['card_09:1', 'card_10:1'],
    });
    const outcome = playCatchYourBreath(
      started,
      'player-1',
      'card_18:1',
      sequenceRandom([]),
    );

    expect(outcome.state.phase).toBe('awaiting_card_effect');
    expect(currentCardEffectResponder(outcome.state)).toBe('player-1');
    expect(outcome.privateResult.drawnCardInstanceIds).toEqual([
      'card_10:1',
      'card_09:1',
    ]);
    const originalPendingState = structuredClone(outcome.state);
    expect(() =>
      respondToCardEffectDiscard(outcome.state, 'player-1', 'card_18:1'),
    ).toThrow(/must be in the responder hand/);
    expect(outcome.state).toEqual(originalPendingState);
    const completed = respondToCardEffectDiscard(
      outcome.state,
      'player-1',
      'card_09:1',
    );

    expect(completed.state.phase).toBe('active_turn');
    expect(completed.state.players['player-1'].hand).toEqual(['card_10:1']);
    expect(completed.state.discardPile).toEqual(['card_18:1', 'card_09:1']);
  });

  it('applies Patch Up and Spotlight with their public and private results', () => {
    const patched = playPatchUp(
      activeState(
        { 'player-1': ['card_20:1'] },
        { 'player-1': 2 },
        { 'player-1': 3 },
      ),
      'player-1',
      'card_20:1',
    );
    expect(patched.players['player-1'].hearts).toBe(3);
    expect(patched.players['player-1'].suspicion).toBe(2);

    const spotlight = playSpotlight(
      matchStateSchema.parse({
        ...activeState({ 'player-1': ['card_23:1'] }, {}, { 'player-2': 2 }),
        drawPile: ['card_09:1'],
      }),
      'player-1',
      'card_23:1',
      sequenceRandom([]),
    );
    expect(spotlight.publicResult.suspicionByPlayerId['player-2']).toBe(2);
    expect(spotlight.privateResult.drawnCardInstanceId).toBe('card_09:1');
    expect(spotlight.state.players['player-1'].hand).toEqual(['card_09:1']);
  });
});
