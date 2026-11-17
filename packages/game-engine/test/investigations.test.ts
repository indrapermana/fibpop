import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import {
  basicObserve,
  grantEvidence,
  playInvestigation,
  type InvestigationDefense,
} from '../src/investigations.js';
import { adjustSuspicion } from '../src/suspicion.js';
import { matchStateSchema } from '../src/state.js';
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

function activeState(hands: Record<string, string[]> = {}) {
  const started = beginTurn(fixture.initialState, {
    next: () => fixture.randomSequence[0],
  });
  const players = Object.fromEntries(
    started.seatOrder.map((playerId) => [
      playerId,
      { ...started.players[playerId], hand: hands[playerId] ?? [] },
    ]),
  );

  return matchStateSchema.parse({
    ...started,
    drawPile: [],
    discardPile: [],
    players,
  });
}

function play(
  state: ReturnType<typeof activeState>,
  cardInstanceId: string,
  targetPlayerId = 'player-2',
  defense?: InvestigationDefense,
  random: () => number = () => 0,
) {
  return playInvestigation(state, {
    actorPlayerId: 'player-1',
    targetPlayerId,
    cardInstanceId,
    random: { next: random },
    ...(defense ? { defense } : {}),
  });
}

describe('Evidence and investigations', () => {
  it('limits each Evidence kind to one marker per investigator and suspect', () => {
    const state = activeState();
    const withClue = grantEvidence(state, 'player-1', 'player-2', 'clue');
    const duplicateClue = grantEvidence(
      withClue,
      'player-1',
      'player-2',
      'clue',
    );
    const withBehavior = grantEvidence(
      duplicateClue,
      'player-1',
      'player-2',
      'behavior',
    );
    const otherInvestigator = grantEvidence(
      withBehavior,
      'player-3',
      'player-2',
      'clue',
    );

    expect(duplicateClue).toBe(withClue);
    expect(withBehavior.players['player-1'].evidence['player-2']).toEqual({
      clue: true,
      behavior: true,
    });
    expect(otherInvestigator.players['player-3'].evidence['player-2']).toEqual({
      clue: true,
      behavior: false,
    });
  });

  it('spends one action for Basic Observe and awards qualifying Behavior once', () => {
    const state = activeState();
    const qualifyingState = matchStateSchema.parse({
      ...state,
      publicActionHistory: [
        { playerId: 'player-2', kind: 'successful_attack' },
      ],
    });

    const first = basicObserve(qualifyingState, 'player-1', 'player-2');
    const duplicate = basicObserve(first.state, 'player-1', 'player-2');

    expect(first.evidenceAdded).toBe(true);
    expect(first.state.actionsRemaining).toBe(1);
    expect(duplicate.evidenceAdded).toBe(false);
    expect(duplicate.state.actionsRemaining).toBe(0);
    expect(duplicate.state.version).toBe(qualifyingState.version + 2);
  });

  it('spends Basic Observe even when the target has no qualifying history', () => {
    const state = activeState();
    const result = basicObserve(state, 'player-1', 'player-2');

    expect(result.evidenceAdded).toBe(false);
    expect(result.state.actionsRemaining).toBe(1);
    expect(result.state.players['player-1'].evidence).toEqual({});
  });

  it('grants Look Back Behavior only for a qualifying public action', () => {
    const state = activeState({
      'player-1': ['card_09:1'],
    });
    const noHistory = play(state, 'card_09:1');
    const qualifyingState = matchStateSchema.parse({
      ...state,
      publicActionHistory: [
        { playerId: 'player-2', kind: 'noisy_manipulation' },
      ],
    });
    const withHistory = play(qualifyingState, 'card_09:1');

    expect(noHistory.evidenceAdded).toBe(false);
    expect(noHistory.state.actionsRemaining).toBe(1);
    expect(withHistory.evidenceAdded).toBe(true);
    expect(
      withHistory.state.players['player-1'].evidence['player-2'].behavior,
    ).toBe(true);
  });

  it('grants Clue and returns Follow the Trail inspection privately', () => {
    const state = activeState({
      'player-1': ['card_10:1'],
      'player-2': ['target-card-a', 'target-card-b'],
    });
    const outcome = play(state, 'card_10:1', 'player-2', undefined, () => 0.75);

    expect(outcome.actionCost).toBe(1);
    expect(outcome.evidenceAdded).toBe(true);
    expect(outcome.privateResult.inspectedCardInstanceId).toBe('target-card-b');
    expect(outcome.privateResult.drawnCardInstanceId).toBeNull();
    expect(outcome.state.players['player-1'].evidence['player-2'].clue).toBe(
      true,
    );
    expect(outcome.state.players['player-2'].hand).toEqual([
      'target-card-a',
      'target-card-b',
    ]);
    expect(outcome.state.discardPile).toEqual(['card_10:1']);
    expect(outcome.state).not.toHaveProperty('privateResult');
  });

  it('draws for Peek when the target hand is empty without inspecting a card', () => {
    const state = matchStateSchema.parse({
      ...activeState({
        'player-1': ['card_11:1'],
        'player-2': [],
      }),
      drawPile: ['drawn-card'],
    });
    const outcome = play(state, 'card_11:1', 'player-2', undefined, () => {
      throw new Error('No random choice is needed for an empty hand or pile');
    });

    expect(outcome.privateResult.inspectedCardInstanceId).toBeNull();
    expect(outcome.privateResult.drawnCardInstanceId).toBe('drawn-card');
    expect(outcome.state.players['player-1'].hand).toEqual(['drawn-card']);
    expect(outcome.state.discardPile).toEqual(['card_11:1']);
  });

  it('grants Check Alibi Clue and privately reveals only a recorded Action card', () => {
    const state = activeState({
      'player-1': ['card_12:1'],
      'player-2': [],
    });
    const withAction = matchStateSchema.parse({
      ...state,
      players: {
        ...state.players,
        'player-2': {
          ...state.players['player-2'],
          lastPlayedActionCardInstanceId: 'card_18:1',
        },
      },
    });
    const outcome = play(withAction, 'card_12:1');

    expect(outcome.privateResult.revealedActionCardInstanceId).toBe(
      'card_18:1',
    );
    expect(outcome.state.players['player-1'].evidence['player-2'].clue).toBe(
      true,
    );
    expect(
      outcome.state.players['player-1'].lastPlayedActionCardInstanceId,
    ).toBe('card_12:1');

    const noAction = play(state, 'card_12:1');
    expect(noAction.privateResult.revealedActionCardInstanceId).toBeNull();
    expect(noAction.state.players['player-1'].evidence['player-2'].clue).toBe(
      true,
    );
  });

  it('keeps Extra Clue Evidence when the target discards to prevent inspection', () => {
    const state = activeState({
      'player-1': ['card_22:1'],
      'player-2': ['discard-to-block', 'hidden-card'],
    });
    const outcome = play(state, 'card_22:1', 'player-2', {
      kind: 'discard',
      cardInstanceId: 'discard-to-block',
    });

    expect(outcome.evidenceAdded).toBe(true);
    expect(outcome.privateResult.inspectedCardInstanceId).toBeNull();
    expect(outcome.state.players['player-1'].evidence['player-2'].clue).toBe(
      true,
    );
    expect(outcome.state.players['player-2'].hand).toEqual(['hidden-card']);
    expect(outcome.state.discardPile).toEqual([
      'card_22:1',
      'discard-to-block',
    ]);
  });

  it('lets Misdirection prevent hand inspection without preventing Evidence', () => {
    const state = activeState({
      'player-1': ['card_10:1'],
      'player-2': ['card_24:1', 'hidden-card'],
    });
    const outcome = play(state, 'card_10:1', 'player-2', {
      kind: 'misdirection',
      cardInstanceId: 'card_24:1',
    });

    expect(outcome.evidenceAdded).toBe(true);
    expect(outcome.privateResult.inspectedCardInstanceId).toBeNull();
    expect(outcome.state.players['player-1'].evidence['player-2'].clue).toBe(
      true,
    );
    expect(outcome.state.players['player-2'].hand).toEqual(['hidden-card']);
    expect(outcome.state.discardPile).toEqual(['card_10:1', 'card_24:1']);
  });

  it('makes only the first Investigation against a 3-Suspicion target free each turn', () => {
    const base = activeState({
      'player-1': ['card_09:1', 'card_09:2'],
    });
    const state = matchStateSchema.parse({
      ...base,
      players: {
        ...base.players,
        'player-2': {
          ...base.players['player-2'],
          suspicion: 3,
        },
      },
    });

    const first = play(state, 'card_09:1');
    const second = play(first.state, 'card_09:2');

    expect(first.actionCost).toBe(0);
    expect(first.state.actionsRemaining).toBe(2);
    expect(second.actionCost).toBe(1);
    expect(second.state.actionsRemaining).toBe(1);
    expect(second.state.investigationTargetsThisTurn).toEqual(['player-2']);

    const nextTurn = endTurn(second.state, []);
    expect(nextTurn.investigationTargetsThisTurn).toEqual([]);
  });

  it('does not grant a later free Investigation if the first was played below 3 Suspicion', () => {
    const state = activeState({
      'player-1': ['card_09:1', 'card_09:2'],
    });
    const first = play(state, 'card_09:1');
    const targetAtThree = adjustSuspicion(first.state, 'player-2', 3);
    const second = play(targetAtThree, 'card_09:2');

    expect(first.actionCost).toBe(1);
    expect(second.actionCost).toBe(1);
    expect(second.state.actionsRemaining).toBe(0);
  });

  it('does not apply the Investigation discount to Extra Clue', () => {
    const base = activeState({
      'player-1': ['card_22:1'],
      'player-2': ['target-card'],
    });
    const state = matchStateSchema.parse({
      ...base,
      players: {
        ...base.players,
        'player-2': { ...base.players['player-2'], suspicion: 3 },
      },
    });
    const outcome = play(state, 'card_22:1');

    expect(outcome.actionCost).toBe(1);
    expect(outcome.state.actionsRemaining).toBe(1);
    expect(outcome.state.investigationTargetsThisTurn).toEqual([]);
  });

  it('rejects unowned cards and self-targeted Peek', () => {
    const state = activeState({
      'player-1': ['card_11:1'],
    });

    expect(() => play(state, 'card_10:1')).toThrow(/must be in the current/);
    expect(() =>
      playInvestigation(state, {
        actorPlayerId: 'player-1',
        targetPlayerId: 'player-1',
        cardInstanceId: 'card_11:1',
        random: { next: () => 0 },
      }),
    ).toThrow(/Peek must target another player/);
  });
});
