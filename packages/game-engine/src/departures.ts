import { currentAttackResponder, respondToAttack } from './attacks.js';
import {
  currentAccusationPlayerId,
  removeSecretFinishParticipant,
  respondToAccusation,
  resumeInterruptedTurn,
} from './cornered.js';
import { EngineError } from './errors.js';
import { findImpostorWinner } from './outcomes.js';
import { matchStateSchema, type MatchState } from './state.js';
import { advanceTurnAfterElimination } from './turns.js';

export type PlayerDeparture =
  { kind: 'disconnect' } | { kind: 'forfeit'; nowMs: number };

export function handlePlayerDeparture(
  state: MatchState,
  playerId: string,
  departure: PlayerDeparture,
): MatchState {
  const player = state.players[playerId];
  if (!player || !state.seatOrder.includes(playerId)) {
    throw new EngineError(
      'INVALID_PLAYER',
      'The player must belong to the match',
    );
  }
  if (
    !departure ||
    (departure.kind !== 'disconnect' && departure.kind !== 'forfeit')
  ) {
    throw new EngineError('INVALID_COMMAND', 'Invalid player departure');
  }
  if (departure.kind === 'disconnect') {
    return state;
  }

  if (
    !Number.isSafeInteger(departure.nowMs) ||
    departure.nowMs < 0 ||
    !Number.isFinite(new Date(departure.nowMs).getTime())
  ) {
    throw new EngineError('INVALID_DEADLINE', 'A valid timestamp is required');
  }
  if (
    ![
      'turn_start',
      'active_turn',
      'awaiting_reaction',
      'awaiting_card_effect',
      'awaiting_accusation',
      'awaiting_secret_finish',
      'awaiting_last_chance',
    ].includes(state.phase) ||
    state.winner !== null
  ) {
    throw new EngineError(
      'INVALID_PHASE',
      'A forfeit requires an ongoing match',
    );
  }
  if (player.status === 'eliminated' || player.role === null) {
    throw new EngineError('NOT_ELIGIBLE', 'The player cannot forfeit');
  }
  if (
    state.deadlineUtc !== null &&
    departure.nowMs >= Date.parse(state.deadlineUtc)
  ) {
    throw new EngineError(
      'WINDOW_EXPIRED',
      'Resolve the expired window before the forfeit',
    );
  }

  const updated = matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    players: {
      ...state.players,
      [playerId]: { ...player, status: 'eliminated' },
    },
  });
  if (player.role === 'impostor') {
    return matchStateSchema.parse({
      ...updated,
      phase: 'cancelled',
      currentPlayerId: null,
      deadlineUtc: null,
      pendingAttack: null,
      pendingCardEffect: null,
      pendingCornered: null,
      pendingSecretFinish: null,
      winner: { kind: 'cancelled_no_winner' },
    });
  }

  const winner = findImpostorWinner(updated);
  if (winner) {
    return winner;
  }

  let result = updated;
  if (state.phase === 'turn_start' || state.phase === 'active_turn') {
    if (state.currentPlayerId === playerId) {
      result = advanceTurnAfterElimination(
        matchStateSchema.parse({ ...updated, phase: 'active_turn' }),
      );
    }
  } else if (state.phase === 'awaiting_card_effect') {
    const pending = state.pendingCardEffect;
    if (!pending) {
      throw new EngineError(
        'INVALID_PHASE',
        'A pending card effect is required',
      );
    }
    if (
      pending.actorPlayerId === playerId ||
      (pending.kind === 'stir_the_pot_discards' &&
        pending.targetPlayerIds.includes(playerId))
    ) {
      result = resumeInterruptedTurn(updated);
    }
  } else if (state.phase === 'awaiting_reaction') {
    const pending = state.pendingAttack;
    if (!pending) {
      throw new EngineError('INVALID_PHASE', 'A pending attack is required');
    }
    if (
      pending.attackerPlayerId === playerId ||
      pending.targetPlayerId === playerId
    ) {
      result = resumeInterruptedTurn(updated);
    } else {
      const currentResponder = currentAttackResponder(state);
      const stepInPlayerIds = pending.stepInPlayerIds.filter(
        (id, index) => id !== playerId || index <= pending.stepInIndex,
      );
      result = matchStateSchema.parse({
        ...updated,
        pendingAttack: { ...pending, stepInPlayerIds },
      });
      if (currentResponder === playerId) {
        result = respondToAttack(
          result,
          playerId,
          { kind: 'pass' },
          departure.nowMs,
        );
      }
    }
  } else if (
    state.phase === 'awaiting_accusation' ||
    state.phase === 'awaiting_secret_finish' ||
    state.phase === 'awaiting_last_chance'
  ) {
    const pending = state.pendingCornered;
    if (!pending) {
      throw new EngineError(
        'INVALID_PHASE',
        'A pending Cornered target is required',
      );
    }
    if (pending.targetPlayerId === playerId) {
      result = resumeInterruptedTurn(updated);
    } else if (state.phase === 'awaiting_accusation') {
      const accusationOrderPlayerIds = pending.accusationOrderPlayerIds.filter(
        (id, index) => id !== playerId || index <= pending.accusationIndex,
      );
      result = matchStateSchema.parse({
        ...updated,
        pendingCornered: { ...pending, accusationOrderPlayerIds },
      });
      if (currentAccusationPlayerId(state) === playerId) {
        result = respondToAccusation(
          result,
          playerId,
          { kind: 'pass' },
          departure.nowMs,
        );
      }
    } else if (state.phase === 'awaiting_secret_finish') {
      result = removeSecretFinishParticipant(updated, playerId);
    }
  }

  return matchStateSchema.parse({ ...result, version: state.version + 1 });
}
