import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  currentAttackResponder,
  playSafePlace,
  respondToAttack,
  startAttack,
} from '../src/attacks.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import { matchStateSchema, type MatchState } from '../src/state.js';
import { beginTurn, endTurn } from '../src/turns.js';

const fixturePath = fileURLToPath(
  new URL(
    '../../../shared/fixtures/m1-turn-start-recycle.json',
    import.meta.url,
  ),
);
const fixture = turnStartFixtureSchema.parse(
  JSON.parse(readFileSync(fixturePath, 'utf8')),
);
const FIXED_NOW_MS = Date.UTC(2026, 10, 17);

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

function passAllReactions(state: MatchState): MatchState {
  let nextState = state;
  while (nextState.phase === 'awaiting_reaction') {
    const responderPlayerId = currentAttackResponder(nextState);
    if (responderPlayerId === null) {
      throw new Error('Pending attack must have an eligible responder');
    }

    nextState = respondToAttack(
      nextState,
      responderPlayerId,
      { kind: 'pass' },
      FIXED_NOW_MS,
    );
  }

  return nextState;
}

describe('attacks and reactions', () => {
  it('starts a valid attack, spends one action, and asks the target first', () => {
    const state = activeState({ 'player-1': ['card_01:1'] });
    const nextState = startAttack(state, 'player-1', 'player-2', 'card_01:1');

    expect(nextState.phase).toBe('awaiting_reaction');
    expect(nextState.actionsRemaining).toBe(1);
    expect(nextState.attacksUsedThisTurn).toBe(1);
    expect(nextState.players['player-1'].hand).toEqual([]);
    expect(nextState.players['player-1'].lastPlayedActionCardInstanceId).toBe(
      'card_01:1',
    );
    expect(nextState.discardPile).toEqual(['card_01:1']);
    expect(nextState.pendingAttack?.stepInPlayerIds).toEqual([
      'player-3',
      'player-4',
      'player-1',
    ]);
    expect(currentAttackResponder(nextState)).toBe('player-2');
  });

  it('rejects invalid attack cards and targets without changing state', () => {
    const state = activeState({ 'player-1': ['card_01:1'] });
    const original = structuredClone(state);

    expect(() =>
      startAttack(state, 'player-1', 'player-2', 'card_02:1'),
    ).toThrow(/must be in the player hand/);
    expect(() =>
      startAttack(state, 'player-1', 'player-1', 'card_01:1'),
    ).toThrow(/Attack target must be another Active player/);
    expect(state).toEqual(original);
  });

  it('lets the target use one Defense card and ends the reaction sequence', () => {
    const state = activeState({
      'player-1': ['card_01:1'],
      'player-2': ['card_05:1', 'card_07:1'],
    });
    const attack = startAttack(state, 'player-1', 'player-2', 'card_01:1');
    const defended = respondToAttack(attack, 'player-2', {
      kind: 'defend',
      cardInstanceId: 'card_05:1',
    });

    expect(defended.phase).toBe('active_turn');
    expect(defended.pendingAttack).toBeNull();
    expect(defended.players['player-2'].hearts).toBe(3);
    expect(defended.players['player-2'].hand).toEqual(['card_07:1']);
    expect(defended.discardPile).toEqual(['card_01:1', 'card_05:1']);
    expect(defended.publicActionHistory).toEqual([]);
    expect(defended.players['player-1'].suspicion).toBe(0);
  });

  it('applies Deny It Suspicion removal and Countercheck Evidence', () => {
    const denyState = activeState(
      {
        'player-1': ['card_01:1'],
        'player-2': ['card_06:1'],
      },
      {},
      { 'player-2': 2 },
    );
    const denied = respondToAttack(
      startAttack(denyState, 'player-1', 'player-2', 'card_01:1'),
      'player-2',
      { kind: 'defend', cardInstanceId: 'card_06:1' },
    );

    expect(denied.players['player-2'].suspicion).toBe(1);
    expect(denied.players['player-2'].hearts).toBe(3);

    const countercheckState = matchStateSchema.parse({
      ...activeState({
        'player-1': ['card_01:1'],
        'player-2': ['card_08:1'],
      }),
      publicActionHistory: [
        { playerId: 'player-1', kind: 'noisy_manipulation' },
      ],
    });
    const counterchecked = respondToAttack(
      startAttack(countercheckState, 'player-1', 'player-2', 'card_01:1'),
      'player-2',
      { kind: 'defend', cardInstanceId: 'card_08:1' },
    );

    expect(counterchecked.players['player-2'].evidence['player-1']).toEqual({
      clue: false,
      behavior: true,
    });
    expect(counterchecked.publicActionHistory).toEqual(
      countercheckState.publicActionHistory,
    );
  });

  it('offers Step In clockwise only after the target passes', () => {
    const state = activeState({
      'player-1': ['card_01:1'],
      'player-2': [],
      'player-3': ['card_07:1'],
    });
    const attack = startAttack(state, 'player-1', 'player-2', 'card_01:1');

    expect(() => respondToAttack(attack, 'player-4', { kind: 'pass' })).toThrow(
      /current attack responder/,
    );
    expect(() =>
      respondToAttack(attack, 'player-2', {
        kind: 'step_in',
        cardInstanceId: 'card_07:1',
      }),
    ).toThrow(/may defend or pass/);

    const afterTargetPass = respondToAttack(attack, 'player-2', {
      kind: 'pass',
    });
    expect(currentAttackResponder(afterTargetPass)).toBe('player-3');

    const steppedIn = respondToAttack(afterTargetPass, 'player-3', {
      kind: 'step_in',
      cardInstanceId: 'card_07:1',
    });
    expect(steppedIn.phase).toBe('active_turn');
    expect(steppedIn.players['player-2'].hearts).toBe(3);
    expect(steppedIn.players['player-3'].hand).toEqual([]);
    expect(steppedIn.discardPile).toEqual(['card_01:1', 'card_07:1']);
    expect(steppedIn.publicActionHistory).toEqual([]);
  });

  it('deals one Heart only after all responders pass and records successful damage', () => {
    const state = activeState({ 'player-1': ['card_01:1'] }, { 'player-2': 2 });
    const attack = startAttack(state, 'player-1', 'player-2', 'card_01:1');
    const damaged = passAllReactions(attack);

    expect(damaged.phase).toBe('active_turn');
    expect(damaged.players['player-2'].hearts).toBe(1);
    expect(damaged.players['player-1'].suspicion).toBe(1);
    expect(damaged.suspicionAwardedForDamageThisTurn).toBe(true);
    expect(damaged.publicActionHistory).toEqual([
      { playerId: 'player-1', kind: 'successful_attack' },
    ]);
  });

  it('requires and applies Double Down discard only when damage succeeds', () => {
    const state = activeState({
      'player-1': ['card_02:1'],
      'player-2': ['card_09:1'],
    });
    const attack = startAttack(state, 'player-1', 'player-2', 'card_02:1');
    expect(() => respondToAttack(attack, 'player-2', { kind: 'pass' })).toThrow(
      /must select a card for Double Down/,
    );
    const targetPass = respondToAttack(attack, 'player-2', {
      kind: 'pass',
      discardCardInstanceId: 'card_09:1',
    });
    const damaged = passAllReactions(targetPass);

    expect(damaged.players['player-2'].hand).toEqual([]);
    expect(damaged.players['player-2'].hearts).toBe(2);
    expect(damaged.discardPile).toEqual(['card_02:1', 'card_09:1']);

    const blockedState = activeState({
      'player-1': ['card_02:1'],
      'player-2': ['card_05:1', 'card_09:2'],
    });
    const blocked = respondToAttack(
      startAttack(blockedState, 'player-1', 'player-2', 'card_02:1'),
      'player-2',
      { kind: 'defend', cardInstanceId: 'card_05:1' },
    );
    expect(blocked.players['player-2'].hand).toEqual(['card_09:2']);
  });

  it('publicly reveals Callout data and grants Corner Them Evidence despite a block', () => {
    const calloutBase = activeState({
      'player-1': ['card_03:1'],
      'player-2': ['card_05:1'],
    });
    const calloutState = matchStateSchema.parse({
      ...calloutBase,
      players: {
        ...calloutBase.players,
        'player-2': {
          ...calloutBase.players['player-2'],
          lastPlayedActionCardInstanceId: 'card_14:1',
        },
      },
    });
    const callout = startAttack(
      calloutState,
      'player-1',
      'player-2',
      'card_03:1',
    );
    expect(callout.pendingAttack?.calloutRevealedActionCardInstanceId).toBe(
      'card_14:1',
    );

    const cornerThemBase = activeState(
      {
        'player-1': ['card_04:1'],
        'player-2': ['card_05:2'],
      },
      {},
      { 'player-2': 2 },
    );
    const cornerThemState = matchStateSchema.parse({
      ...cornerThemBase,
      publicActionHistory: [
        { playerId: 'player-2', kind: 'noisy_manipulation' },
      ],
    });
    const attack = startAttack(
      cornerThemState,
      'player-1',
      'player-2',
      'card_04:1',
    );
    expect(attack.players['player-1'].evidence['player-2']).toEqual({
      clue: false,
      behavior: true,
    });

    const blocked = respondToAttack(attack, 'player-2', {
      kind: 'defend',
      cardInstanceId: 'card_05:2',
    });
    expect(blocked.players['player-2'].hearts).toBe(3);
    expect(blocked.players['player-1'].evidence['player-2']).toEqual({
      clue: false,
      behavior: true,
    });
  });

  it('enters Cornered after the successful damage and preserves attack context', () => {
    const active = activeState(
      { 'player-1': ['card_04:1'] },
      { 'player-2': 1 },
    );
    const state = matchStateSchema.parse({
      ...active,
      players: {
        ...active.players,
        'player-1': {
          ...active.players['player-1'],
          role: 'impostor',
        },
        'player-2': {
          ...active.players['player-2'],
          role: 'innocent',
        },
        'player-3': {
          ...active.players['player-3'],
          role: 'innocent',
          evidence: {
            'player-2': { clue: true, behavior: true },
          },
        },
        'player-4': {
          ...active.players['player-4'],
          role: 'innocent',
        },
      },
    });
    const cornered = passAllReactions(
      startAttack(state, 'player-1', 'player-2', 'card_04:1'),
    );

    expect(cornered.phase).toBe('awaiting_accusation');
    expect(cornered.players['player-2'].status).toBe('cornered');
    expect(cornered.players['player-2'].hearts).toBe(0);
    expect(cornered.pendingCornered).toEqual({
      attackerPlayerId: 'player-1',
      targetPlayerId: 'player-2',
      attackCardInstanceId: 'card_04:1',
      accusationOrderPlayerIds: ['player-3'],
      accusationIndex: 0,
      secretFinishResolved: false,
    });
    expect(cornered.deadlineUtc).toBe(
      new Date(FIXED_NOW_MS + 10_000).toISOString(),
    );
    expect(cornered.pendingAttack).toBeNull();
    expect(cornered.publicActionHistory).toEqual([
      { playerId: 'player-1', kind: 'successful_attack' },
    ]);
  });

  it('Safe Place prevents the next damage without recording a successful attack', () => {
    const state = matchStateSchema.parse({
      ...activeState({ 'player-1': ['card_01:1'] }),
      activeEffects: [
        {
          type: 'safe_place',
          casterPlayerId: 'player-4',
          targetPlayerId: 'player-2',
        },
      ],
    });
    const protectedState = passAllReactions(
      startAttack(state, 'player-1', 'player-2', 'card_01:1'),
    );

    expect(protectedState.phase).toBe('active_turn');
    expect(protectedState.players['player-2'].hearts).toBe(3);
    expect(protectedState.activeEffects).toEqual([]);
    expect(protectedState.players['player-1'].suspicion).toBe(0);
    expect(protectedState.publicActionHistory).toEqual([]);
  });

  it('keeps Safe Place when another Defense card already prevents the attack', () => {
    const state = matchStateSchema.parse({
      ...activeState({
        'player-1': ['card_01:1'],
        'player-2': ['card_05:1'],
      }),
      activeEffects: [
        {
          type: 'safe_place',
          casterPlayerId: 'player-4',
          targetPlayerId: 'player-2',
        },
      ],
    });
    const defended = respondToAttack(
      startAttack(state, 'player-1', 'player-2', 'card_01:1'),
      'player-2',
      { kind: 'defend', cardInstanceId: 'card_05:1' },
    );

    expect(defended.activeEffects).toEqual(state.activeEffects);
    expect(defended.players['player-2'].hearts).toBe(3);
  });

  it('plays one Safe Place on an Active target and rejects a second shield', () => {
    const state = activeState({
      'player-1': ['card_21:1', 'card_21:2'],
    });
    const protectedState = playSafePlace(
      state,
      'player-1',
      'player-2',
      'card_21:1',
    );

    expect(protectedState.actionsRemaining).toBe(1);
    expect(
      protectedState.players['player-1'].lastPlayedActionCardInstanceId,
    ).toBe('card_21:1');
    expect(protectedState.activeEffects).toEqual([
      {
        type: 'safe_place',
        casterPlayerId: 'player-1',
        targetPlayerId: 'player-2',
      },
    ]);
    expect(protectedState.discardPile).toEqual(['card_21:1']);
    expect(() =>
      playSafePlace(protectedState, 'player-1', 'player-2', 'card_21:2'),
    ).toThrow(/already has a Safe Place shield/);
  });

  it('expires Safe Place on the caster next scheduled turn', () => {
    let state = playSafePlace(
      activeState({ 'player-1': ['card_21:1'] }),
      'player-1',
      'player-2',
      'card_21:1',
    );

    for (const expectedPlayerId of ['player-2', 'player-3', 'player-4']) {
      state = endTurn(state, []);
      expect(state.currentPlayerId).toBe(expectedPlayerId);
      state = beginTurn(state, { next: () => 0.5 });
      expect(state.activeEffects).toHaveLength(1);
    }

    state = endTurn(state, []);
    expect(state.currentPlayerId).toBe('player-1');
    expect(state.activeEffects).toEqual([]);
  });
});
