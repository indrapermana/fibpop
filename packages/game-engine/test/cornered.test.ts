import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { describe, expect, it } from 'vitest';

import {
  currentAccusationPlayerId,
  currentLastChancePlayerId,
  expireAccusationOffer,
  expireLastChanceWindow,
  expireSecretFinishWindow,
  beginCorneredResolution,
  passLastChance,
  playLastChance,
  respondToAccusation,
  submitSecretFinishChoice,
} from '../src/cornered.js';
import {
  currentAttackResponder,
  respondToAttack,
  startAttack,
} from '../src/attacks.js';
import { turnStartFixtureSchema } from '../src/golden-fixture.js';
import {
  matchStateSchema,
  type MatchState,
  type PlayerRole,
} from '../src/state.js';
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
const NOW_MS = Date.UTC(2026, 10, 17, 0, 0, 0);

interface CorneredStateOptions {
  eligibleAccuserIds?: string[];
  eliminatedPlayerIds?: string[];
  corneredPlayerIds?: string[];
  hands?: Record<string, string[]>;
  roles?: Record<string, PlayerRole>;
  accusationUsed?: string[];
  keepCoverSlots?: boolean;
}

function deadline(state: MatchState): number {
  if (!state.deadlineUtc) throw new Error('Expected a deadline');
  return Date.parse(state.deadlineUtc);
}

function finishAccusationSlots(state: MatchState): MatchState {
  let next = state;
  while (next.phase === 'awaiting_accusation') {
    next = expireAccusationOffer(next, deadline(next));
  }
  return next;
}

function createCorneredState(options: CorneredStateOptions = {}): MatchState {
  const started = beginTurn(fixture.initialState, { next: () => 0.5 });
  const eligibleAccuserIds = new Set(
    options.eligibleAccuserIds ?? ['player-1'],
  );
  const players = Object.fromEntries(
    started.seatOrder.map((playerId) => {
      const base = started.players[playerId];
      const role =
        options.roles?.[playerId] ??
        (playerId === 'player-4' ? 'impostor' : 'innocent');
      return [
        playerId,
        {
          ...base,
          role,
          status: options.eliminatedPlayerIds?.includes(playerId)
            ? 'eliminated'
            : options.corneredPlayerIds?.includes(playerId)
              ? 'cornered'
              : 'active',
          hearts:
            playerId === 'player-2'
              ? 1
              : options.corneredPlayerIds?.includes(playerId)
                ? 0
                : 3,
          hand:
            playerId === 'player-1'
              ? ['card_01:1']
              : (options.hands?.[playerId] ?? []),
          evidence: eligibleAccuserIds.has(playerId)
            ? {
                'player-2': { clue: true, behavior: true },
              }
            : {},
          accusationUsed: options.accusationUsed?.includes(playerId) ?? false,
        },
      ];
    }),
  );
  const state = matchStateSchema.parse({
    ...started,
    drawPile: [],
    discardPile: [],
    players,
    accusationUsed: options.accusationUsed ?? [],
  });
  let attack = startAttack(state, 'player-1', 'player-2', 'card_01:1');

  while (attack.phase === 'awaiting_reaction') {
    const responderPlayerId = currentAttackResponder(attack);
    if (responderPlayerId === null) {
      throw new Error('Pending attack must have an eligible responder');
    }

    attack = respondToAttack(
      attack,
      responderPlayerId,
      { kind: 'pass' },
      NOW_MS,
    );
  }

  return eligibleAccuserIds.size === 0 && !options.keepCoverSlots
    ? finishAccusationSlots(attack)
    : attack;
}

describe('Cornered resolution', () => {
  it('prioritizes an eligible attacker, then offers clockwise to remaining eligible Innocents', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1', 'player-3', 'player-4'],
    });

    expect(state.phase).toBe('awaiting_accusation');
    expect(state.pendingCornered?.accusationOrderPlayerIds).toEqual([
      'player-1',
      'player-3',
      'player-4',
    ]);
    expect(currentAccusationPlayerId(state)).toBe('player-1');
    expect(state.deadlineUtc).toBe(new Date(NOW_MS + 10_000).toISOString());
  });

  it('pads the attacker slot before the next eligible player', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-3', 'player-4'],
    });

    expect(currentAccusationPlayerId(state)).toBe('player-1');
    expect(() =>
      respondToAccusation(state, 'player-1', { kind: 'accuse' }, NOW_MS + 1),
    ).toThrow(/not eligible/);
    const next = expireAccusationOffer(state, deadline(state));
    expect(currentAccusationPlayerId(next)).toBe('player-3');
  });

  it('does not offer an accusation to a player who already used theirs', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1', 'player-3'],
      accusationUsed: ['player-1'],
    });

    expect(() =>
      respondToAccusation(state, 'player-1', { kind: 'accuse' }, NOW_MS + 1),
    ).toThrow(/not eligible/);
    expect(
      currentAccusationPlayerId(expireAccusationOffer(state, deadline(state))),
    ).toBe('player-3');
  });

  it('uses cover slots even when nobody is eligible', () => {
    const cover = createCorneredState({
      eligibleAccuserIds: [],
      keepCoverSlots: true,
    });
    expect(cover.pendingCornered?.accusationOrderPlayerIds).toEqual([
      'player-1',
      'player-3',
      'player-4',
    ]);
    const state = finishAccusationSlots(cover);

    expect(state.phase).toBe('awaiting_secret_finish');
    expect(state.pendingCornered?.accusationOrderPlayerIds).toEqual([
      'player-1',
      'player-3',
      'player-4',
    ]);
    expect(state.pendingCornered?.secretFinishResolved).toBe(false);
    expect(state.pendingSecretFinish?.eligiblePlayerIds).toEqual([
      'player-1',
      'player-3',
      'player-4',
    ]);
  });

  it('does not restart an accusation offer and reset its deadline', () => {
    const state = createCorneredState();

    expect(() => beginCorneredResolution(state, NOW_MS + 1)).toThrow(
      /already started/,
    );
  });

  it('rejects late accusations and advances a timed-out offer', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1', 'player-3'],
    });
    const deadline = NOW_MS + 10_000;

    expect(() => expireAccusationOffer(state, deadline - 1)).toThrow(
      /has not expired/,
    );
    expect(() =>
      respondToAccusation(state, 'player-1', { kind: 'accuse' }, deadline),
    ).toThrow(/has expired/);

    const nextOffer = expireAccusationOffer(state, deadline);
    expect(currentAccusationPlayerId(nextOffer)).toBe('player-3');
    expect(nextOffer.deadlineUtc).toBe(
      new Date(deadline + 10_000).toISOString(),
    );
    expect(nextOffer.players['player-1'].accusationUsed).toBe(false);
  });

  it('keeps an early pass sealed until the slot deadline and rejects duplicate responses', () => {
    const state = createCorneredState();
    const passed = respondToAccusation(
      state,
      'player-1',
      { kind: 'pass' },
      NOW_MS + 1,
    );
    expect(currentAccusationPlayerId(passed)).toBe('player-1');
    expect(() =>
      respondToAccusation(passed, 'player-1', { kind: 'accuse' }, NOW_MS + 2),
    ).toThrow(/already submitted/);
    expect(() => expireAccusationOffer(passed, deadline(passed) - 1)).toThrow(
      /not expired/,
    );
    expect(
      currentAccusationPlayerId(
        expireAccusationOffer(passed, deadline(passed)),
      ),
    ).toBe('player-3');
  });

  it('rejects an invalid accusation response kind', () => {
    const state = createCorneredState();

    expect(() =>
      // @ts-expect-error Exercise malformed runtime input at the engine boundary.
      respondToAccusation(state, 'player-1', { kind: 'invalid' }, NOW_MS + 1),
    ).toThrow(/must be pass or accuse/);
  });

  it('ends immediately with the Innocent accuser on a correct accusation', () => {
    const state = createCorneredState({
      roles: { 'player-2': 'impostor', 'player-4': 'innocent' },
    });
    const finished = respondToAccusation(
      state,
      'player-1',
      { kind: 'accuse' },
      NOW_MS + 1,
    );

    expect(finished.phase).toBe('finished');
    expect(finished.winner).toEqual({
      kind: 'winner',
      playerId: 'player-1',
    });
    expect(finished.players['player-1'].accusationUsed).toBe(true);
    expect(finished.accusationUsed).toContain('player-1');
    expect(finished.pendingCornered).toBeNull();
    expect(finished.pendingSecretFinish).toBeNull();
  });

  it('eliminates both Innocents on a wrong accusation and advances an eliminated turn owner', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1', 'player-3'],
    });
    const resolved = respondToAccusation(
      state,
      'player-1',
      { kind: 'accuse' },
      NOW_MS + 1,
    );

    expect(resolved.players['player-1'].status).toBe('eliminated');
    expect(resolved.players['player-2'].status).toBe('eliminated');
    expect(resolved.players['player-1'].accusationUsed).toBe(true);
    expect(resolved.currentPlayerId).toBe('player-3');
    expect(resolved.phase).toBe('turn_start');
    expect(resolved.pendingCornered).toBeNull();
  });

  it('awards the Impostor a win when a wrong accusation eliminates the final Innocents', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1'],
      eliminatedPlayerIds: ['player-4'],
      roles: { 'player-3': 'impostor', 'player-4': 'innocent' },
    });
    const resolved = respondToAccusation(
      state,
      'player-1',
      { kind: 'accuse' },
      NOW_MS + 1,
    );

    expect(resolved.phase).toBe('finished');
    expect(resolved.winner).toEqual({
      kind: 'winner',
      playerId: 'player-3',
    });
    expect(resolved.players['player-1'].status).toBe('eliminated');
    expect(resolved.players['player-2'].status).toBe('eliminated');
  });

  it('awards a Cornered Impostor the win after the final wrong accusation', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1'],
      eliminatedPlayerIds: ['player-4'],
      corneredPlayerIds: ['player-3'],
      roles: { 'player-3': 'impostor', 'player-4': 'innocent' },
    });
    const result = respondToAccusation(
      state,
      'player-1',
      { kind: 'accuse' },
      NOW_MS + 1,
    );
    expect(result.winner).toEqual({ kind: 'winner', playerId: 'player-3' });
    expect(result.players['player-3']).toMatchObject({
      status: 'cornered',
      hearts: 0,
    });
  });

  it('opens a sealed Secret Finish window only after all accusation offers pass', () => {
    const state = createCorneredState({
      eligibleAccuserIds: ['player-1', 'player-3'],
    });
    const firstPass = respondToAccusation(
      state,
      'player-1',
      { kind: 'pass' },
      NOW_MS + 1,
    );
    expect(firstPass.phase).toBe('awaiting_accusation');

    const secondOffer = expireAccusationOffer(firstPass, deadline(firstPass));
    const lastPass = respondToAccusation(
      secondOffer,
      'player-3',
      { kind: 'pass' },
      NOW_MS + 10_001,
    );
    expect(lastPass.phase).toBe('awaiting_accusation');
    const finishedSlots = finishAccusationSlots(lastPass);
    expect(finishedSlots.phase).toBe('awaiting_secret_finish');
    expect(finishedSlots.pendingSecretFinish?.eligiblePlayerIds).toEqual([
      'player-1',
      'player-3',
      'player-4',
    ]);
    expect(finishedSlots.deadlineUtc).toBe(
      new Date(NOW_MS + 40_000).toISOString(),
    );
  });

  it('rejects an Innocent finish choice without changing the sealed window', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
    });
    expect(state.phase).toBe('awaiting_secret_finish');
    const original = structuredClone(state);

    expect(() =>
      submitSecretFinishChoice(
        state,
        'player-1',
        'finish',
        deadline(state) - 9_999,
      ),
    ).toThrow(/not valid for this player/);
    expect(state).toEqual(original);
  });

  it('rejects an invalid Secret Finish choice', () => {
    const state = createCorneredState({ eligibleAccuserIds: [] });

    expect(() =>
      submitSecretFinishChoice(
        state,
        'player-1',
        // @ts-expect-error Exercise malformed runtime input at the engine boundary.
        'invalid',
        deadline(state) - 9_999,
      ),
    ).toThrow(/must be finish or pass/);
  });

  it('buffers an authorized Secret Finish until the deadline without revealing its actor', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
    });
    const firstPass = submitSecretFinishChoice(
      state,
      'player-1',
      'pass',
      deadline(state) - 9_999,
    );
    const secondPass = submitSecretFinishChoice(
      firstPass,
      'player-3',
      'pass',
      deadline(state) - 9_998,
    );
    const submitted = submitSecretFinishChoice(
      secondPass,
      'player-4',
      'finish',
      deadline(state) - 9_997,
    );
    expect(submitted.phase).toBe('awaiting_secret_finish');
    expect(submitted.players['player-2'].status).toBe('cornered');
    const finished = expireSecretFinishWindow(submitted, deadline(submitted));

    expect(finished.players['player-2'].status).toBe('eliminated');
    expect(finished.phase).toBe('active_turn');
    expect(finished.currentPlayerId).toBe('player-1');
    expect(finished.pendingSecretFinish).toBeNull();
    expect(finished.pendingCornered).toBeNull();
    expect(finished.winner).toBeNull();
  });

  it('wins immediately when Secret Finish eliminates the final Innocent', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      eliminatedPlayerIds: ['player-3', 'player-4'],
      roles: { 'player-1': 'impostor', 'player-4': 'innocent' },
    });
    const submitted = submitSecretFinishChoice(
      state,
      'player-1',
      'finish',
      deadline(state) - 9_999,
    );
    const finished = expireSecretFinishWindow(submitted, deadline(submitted));

    expect(finished.players['player-2'].status).toBe('eliminated');
    expect(finished.phase).toBe('finished');
    expect(finished.winner).toEqual({
      kind: 'winner',
      playerId: 'player-1',
    });
    expect(finished.pendingSecretFinish).toBeNull();
  });

  it('does not award victory when the final Innocent remains Cornered after a pass', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      eliminatedPlayerIds: ['player-3', 'player-4'],
      roles: { 'player-1': 'impostor', 'player-4': 'innocent' },
    });
    const submitted = submitSecretFinishChoice(
      state,
      'player-1',
      'pass',
      deadline(state) - 9_999,
    );
    const window = expireSecretFinishWindow(submitted, deadline(submitted));
    const result = expireLastChanceWindow(window, deadline(window));
    expect(result.phase).toBe('active_turn');
    expect(result.winner).toBeNull();
    expect(result.players['player-2']).toMatchObject({
      status: 'cornered',
      hearts: 0,
    });
  });

  it('uses a pass-only cover window for a Cornered Impostor', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      hands: { 'player-2': ['card_19:1'] },
      roles: { 'player-2': 'impostor', 'player-4': 'innocent' },
    });

    expect(state.phase).toBe('awaiting_secret_finish');
    expect(() =>
      submitSecretFinishChoice(
        state,
        'player-1',
        'finish',
        deadline(state) - 9_999,
      ),
    ).toThrow(/not valid/);
    const result = expireSecretFinishWindow(state, deadline(state));
    expect(result.phase).toBe('awaiting_last_chance');
    expect(currentLastChancePlayerId(result)).toBe('player-2');
  });

  it('keeps the sealed pass window when the Impostor is Cornered', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      corneredPlayerIds: ['player-4'],
    });

    expect(state.phase).toBe('awaiting_secret_finish');
    expect(state.pendingSecretFinish?.eligiblePlayerIds).toEqual([
      'player-1',
      'player-3',
    ]);
  });

  it('treats missing Secret Finish choices as passes when the deadline closes', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      hands: { 'player-2': ['card_19:1'] },
    });
    const submitted = submitSecretFinishChoice(
      state,
      'player-1',
      'pass',
      deadline(state) - 9_999,
    );
    const expiresAt = deadline(state);

    expect(() => expireSecretFinishWindow(submitted, expiresAt - 1)).toThrow(
      /has not expired/,
    );
    const expired = expireSecretFinishWindow(submitted, expiresAt);

    expect(expired.phase).toBe('awaiting_last_chance');
    expect(currentLastChancePlayerId(expired)).toBe('player-2');
    expect(expired.players['player-2'].status).toBe('cornered');
  });

  it('lets the Cornered target play Last Chance only after Secret Finish resolves', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      hands: { 'player-2': ['card_19:1'] },
    });
    const finishedWindow = expireSecretFinishWindow(state, deadline(state));
    const submitted = playLastChance(
      finishedWindow,
      'player-2',
      'card_19:1',
      deadline(finishedWindow) - 1,
    );
    expect(submitted.players['player-2'].status).toBe('cornered');
    expect(() =>
      passLastChance(submitted, 'player-2', deadline(submitted) - 1),
    ).toThrow(/already submitted/);
    expect(() =>
      expireLastChanceWindow(submitted, deadline(submitted) - 1),
    ).toThrow(/not expired/);
    const recovered = expireLastChanceWindow(submitted, deadline(submitted));

    expect(recovered.players['player-2'].status).toBe('active');
    expect(recovered.players['player-2'].hearts).toBe(1);
    expect(recovered.discardPile).toEqual(['card_01:1', 'card_19:1']);
    expect(recovered.phase).toBe('active_turn');
    expect(recovered.pendingCornered).toBeNull();
  });

  it('allows the Cornered target to pass Last Chance and remain Cornered', () => {
    const state = createCorneredState({
      eligibleAccuserIds: [],
      hands: { 'player-2': ['card_19:1'] },
    });
    const window = expireSecretFinishWindow(state, deadline(state));
    const submitted = passLastChance(window, 'player-2', deadline(window) - 1);
    const passed = expireLastChanceWindow(submitted, deadline(submitted));

    expect(passed.phase).toBe('active_turn');
    expect(passed.players['player-2'].status).toBe('cornered');
    expect(passed.players['player-2'].hearts).toBe(0);
    expect(passed.pendingCornered).toBeNull();
    expect(passed.currentPlayerId).toBe('player-1');
  });
});
