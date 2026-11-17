import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

import {
  currentAttackResponder,
  respondToAttack,
  startAttack,
} from '../src/attacks.js';
import {
  expireAccusationOffer,
  expireLastChanceWindow,
  expireSecretFinishWindow,
  passLastChance,
  respondToAccusation,
  submitSecretFinishChoice,
} from '../src/cornered.js';
import {
  applyTransition,
  recordTransition,
  replayTransitions,
} from '../src/events.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import { projectPlayerState, projectPublicState } from '../src/projections.js';
import { matchStateSchema, type MatchState } from '../src/state.js';
import { beginTurn, endTurn } from '../src/turns.js';

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

function deadline(state: MatchState): number {
  if (!state.deadlineUtc) throw new Error('Missing deadline');
  return Date.parse(state.deadlineUtc);
}

function activeState(): MatchState {
  const state = beginTurn(fixture.initialState, { next: () => 0.5 });
  return matchStateSchema.parse({
    ...state,
    drawPile: ['private-deck-card'],
    discardPile: [],
    players: Object.fromEntries(
      state.seatOrder.map((id) => [
        id,
        {
          ...state.players[id],
          role: id === 'player-4' ? 'impostor' : 'innocent',
          hand: id === 'player-1' ? ['card_01:1'] : [`private-${id}-card`],
          evidence:
            id === 'player-1'
              ? { 'player-3': { clue: true, behavior: true } }
              : {},
        },
      ]),
    ),
  });
}

function corneredState(impostorTarget = false, keepSlots = false): MatchState {
  const base = activeState();
  const players = {
    ...base.players,
    'player-2': {
      ...base.players['player-2'],
      hearts: 1,
      role: impostorTarget ? 'impostor' : 'innocent',
    },
    'player-4': {
      ...base.players['player-4'],
      role: impostorTarget ? 'innocent' : 'impostor',
    },
  };
  let state = startAttack(
    matchStateSchema.parse({ ...base, players }),
    'player-1',
    'player-2',
    'card_01:1',
  );
  while (state.phase === 'awaiting_reaction') {
    const responder = currentAttackResponder(state);
    if (!responder) throw new Error('Missing responder');
    state = respondToAttack(state, responder, { kind: 'pass' }, NOW);
  }
  while (!keepSlots && state.phase === 'awaiting_accusation') {
    state = expireAccusationOffer(state, deadline(state));
  }
  return state;
}

describe('authoritative transition replay', () => {
  it('replays randomized draws and later transitions after serialization', () => {
    const initial = fixture.initialState;
    const drawn = beginTurn(initial, { next: () => 0.5 });
    const ended = endTurn(drawn, []);
    const events = JSON.parse(
      JSON.stringify([
        recordTransition(initial, drawn),
        recordTransition(drawn, ended),
      ]),
    );
    expect(replayTransitions(initial, events)).toEqual(ended);
    expect(initial).toEqual(fixture.initialState);
  });

  it('replays a sealed submission and resolution without re-running randomness or a clock', () => {
    const initial = corneredState();
    const submitted = submitSecretFinishChoice(
      initial,
      'player-4',
      'finish',
      deadline(initial) - 9_999,
    );
    const resolved = expireSecretFinishWindow(submitted, deadline(submitted));
    const events = [
      recordTransition(initial, submitted),
      recordTransition(submitted, resolved),
    ];
    expect(
      replayTransitions(initial, JSON.parse(JSON.stringify(events))),
    ).toEqual(resolved);
    expect(events[0].changes.pendingSecretFinish?.submissions).toEqual({
      'player-4': 'finish',
    });
  });

  it('rejects invalid, stale, reordered, and cross-match events', () => {
    const state = fixture.initialState;
    const next = beginTurn(state, { next: () => 0.5 });
    const event = recordTransition(state, next);
    expect(() => applyTransition(next, event)).toThrow(/stale/);
    expect(() =>
      applyTransition(state, { ...event, matchId: 'other' }),
    ).toThrow(/another match/);
    expect(() =>
      applyTransition(state, { ...event, version: event.version + 1 }),
    ).toThrow(/Invalid state transition/);
    expect(() =>
      applyTransition(state, { ...event, changes: { secret: true } }),
    ).toThrow(/Invalid state transition/);
    expect(() => recordTransition(state, state)).toThrow(/version/);
    expect(() => replayTransitions(state, [event, event])).toThrow(/stale/);
  });

  it('copies event data rather than retaining mutable state references', () => {
    const state = fixture.initialState;
    const next = beginTurn(state, { next: () => 0.5 });
    const event = recordTransition(state, next);
    next.players['player-1'].hand.push('later-change');
    expect(
      applyTransition(state, event).players['player-1'].hand,
    ).not.toContain('later-change');
  });
});

describe('public and player projections', () => {
  it.each([4, 8])('uses fixed cover timing with %i Active players', (count) => {
    const base = activeState();
    const extraIds = Array.from(
      { length: count - 4 },
      (_, index) => `player-${index + 5}`,
    );
    const players = {
      ...base.players,
      'player-2': { ...base.players['player-2'], hearts: 1 },
      ...Object.fromEntries(
        extraIds.map((id) => [
          id,
          { ...base.players['player-3'], playerId: id, evidence: {}, hand: [] },
        ]),
      ),
    };
    let state = startAttack(
      matchStateSchema.parse({
        ...base,
        players,
        seatOrder: [...base.seatOrder, ...extraIds],
      }),
      'player-1',
      'player-2',
      'card_01:1',
    );
    while (state.phase === 'awaiting_reaction') {
      const responder = currentAttackResponder(state);
      if (!responder) throw new Error('Missing responder');
      state = respondToAttack(state, responder, { kind: 'pass' }, NOW);
    }
    let slots = 0;
    while (state.phase === 'awaiting_accusation') {
      state = expireAccusationOffer(state, deadline(state));
      slots += 1;
    }
    expect(slots).toBe(count - 1);
    expect(deadline(state)).toBe(NOW + count * 10_000);
    const lastChance = expireSecretFinishWindow(state, deadline(state));
    expect(deadline(lastChance)).toBe(NOW + (count + 1) * 10_000);
    expect(expireLastChanceWindow(lastChance, deadline(lastChance)).phase).toBe(
      'active_turn',
    );
  });

  it('exposes only the viewer’s hand, role, and Evidence', () => {
    const state = activeState();
    const view = projectPlayerState(state, 'player-1');
    expect(view.self).toMatchObject({
      role: 'innocent',
      hand: ['card_01:1'],
      evidence: { 'player-3': { clue: true, behavior: true } },
    });
    expect(view.public.players['player-4']).toMatchObject({
      handCount: 1,
      revealedRole: null,
    });
    const json = JSON.stringify(view);
    expect(json).not.toContain('private-player-4-card');
    expect(json).not.toContain('private-deck-card');
    expect(json).not.toContain('"impostor"');
    expect(() => projectPlayerState(state, 'unknown')).toThrow(/belong/);
  });

  it('projects visible attack information without leaking a private discard choice', () => {
    const initial = activeState();
    const state = matchStateSchema.parse({
      ...initial,
      players: {
        ...initial.players,
        'player-1': { ...initial.players['player-1'], hand: ['card_02:1'] },
      },
    });
    const attack = startAttack(state, 'player-1', 'player-2', 'card_02:1');
    const passed = respondToAttack(attack, 'player-2', {
      kind: 'pass',
      discardCardInstanceId: 'private-player-2-card',
    });
    const view = projectPlayerState(passed, 'player-3');
    expect(view.public.attack).toMatchObject({
      attackerPlayerId: 'player-1',
      targetPlayerId: 'player-2',
      attackCardInstanceId: 'card_02:1',
    });
    expect(JSON.stringify(view)).not.toContain('private-player-2-card');
  });

  it('keeps public views unchanged by sealed choices and private versions', () => {
    const state = corneredState();
    const submitted = submitSecretFinishChoice(
      state,
      'player-4',
      'finish',
      deadline(state) - 9_999,
    );
    expect(projectPublicState(submitted)).toEqual(projectPublicState(state));
    expect(projectPlayerState(submitted, 'player-1')).toEqual(
      projectPlayerState(state, 'player-1'),
    );
    expect(projectPlayerState(submitted, 'player-4').self.prompt).toMatchObject(
      {
        kind: 'secret_choice',
        canFinish: true,
        submitted: true,
      },
    );
  });

  it('presents the same cover window for an Innocent or Impostor target', () => {
    const innocent = corneredState(false);
    const impostor = corneredState(true);
    expect(projectPublicState(innocent)).toEqual(projectPublicState(impostor));
    expect(projectPlayerState(innocent, 'player-1')).toEqual(
      projectPlayerState(impostor, 'player-1'),
    );
    expect(innocent.deadlineUtc).toEqual(impostor.deadlineUtc);
    expect(() =>
      submitSecretFinishChoice(
        impostor,
        'player-1',
        'finish',
        deadline(impostor) - 9_999,
      ),
    ).toThrow(/not valid/);
  });

  it('pads accusation passes and hidden eligibility independently of other players’ Evidence', () => {
    const state = corneredState(false, true);
    const withEvidence = matchStateSchema.parse({
      ...state,
      players: {
        ...state.players,
        'player-3': {
          ...state.players['player-3'],
          evidence: { 'player-2': { clue: true, behavior: true } },
        },
      },
    });
    const first = expireAccusationOffer(state, deadline(state));
    const eligible = expireAccusationOffer(
      withEvidence,
      deadline(withEvidence),
    );
    expect(projectPlayerState(first, 'player-1')).toEqual(
      projectPlayerState(eligible, 'player-1'),
    );
    const passed = respondToAccusation(
      eligible,
      'player-3',
      { kind: 'pass' },
      deadline(eligible) - 1,
    );
    expect(projectPlayerState(first, 'player-1')).toEqual(
      projectPlayerState(passed, 'player-1'),
    );
    expect(currentAttackResponder(passed)).toBeNull();
    expect(expireAccusationOffer(first, deadline(first)).deadlineUtc).toEqual(
      expireAccusationOffer(passed, deadline(passed)).deadlineUtc,
    );
  });

  it('pads Last Chance regardless of the target’s hidden hand or early pass', () => {
    const without = corneredState();
    const withCard = matchStateSchema.parse({
      ...without,
      players: {
        ...without.players,
        'player-2': { ...without.players['player-2'], hand: ['card_19:1'] },
      },
    });
    const cover = expireSecretFinishWindow(without, deadline(without));
    const window = expireSecretFinishWindow(withCard, deadline(withCard));
    expect(projectPlayerState(cover, 'player-1')).toEqual(
      projectPlayerState(window, 'player-1'),
    );
    const passed = passLastChance(window, 'player-2', deadline(window) - 1);
    expect(projectPlayerState(cover, 'player-1')).toEqual(
      projectPlayerState(passed, 'player-1'),
    );
    expect(
      projectPublicState(expireLastChanceWindow(cover, deadline(cover))),
    ).toEqual(
      projectPublicState(expireLastChanceWindow(passed, deadline(passed))),
    );
  });

  it('reveals only eliminated players and the winning accusation target', () => {
    const state = activeState();
    const eliminated = matchStateSchema.parse({
      ...state,
      players: {
        ...state.players,
        'player-2': { ...state.players['player-2'], status: 'eliminated' },
      },
    });
    const view = projectPublicState(eliminated);
    expect(view.players['player-2'].revealedRole).toBe('innocent');
    expect(view.players['player-4'].revealedRole).toBeNull();
    const finished = matchStateSchema.parse({
      ...state,
      phase: 'finished',
      currentPlayerId: null,
      winner: { kind: 'winner', playerId: 'player-1' },
    });
    expect(projectPublicState(finished).players['player-4'].revealedRole).toBe(
      'impostor',
    );
  });

  it('returns detached views that cannot mutate authoritative state', () => {
    const state = activeState();
    const view = projectPlayerState(state, 'player-1');
    view.self.hand.push('changed');
    view.self.evidence['player-3'].clue = false;
    view.public.players['player-4'].hearts = 0;
    expect(state.players['player-1'].hand).toEqual(['card_01:1']);
    expect(state.players['player-1'].evidence['player-3'].clue).toBe(true);
    expect(state.players['player-4'].hearts).toBe(3);
  });
});
