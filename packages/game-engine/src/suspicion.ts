import { EngineError } from './errors.js';
import { matchStateSchema, type MatchState } from './state.js';

export const MAX_SUSPICION = 3;

export function adjustSuspicion(
  state: MatchState,
  playerId: string,
  change: number,
): MatchState {
  if (!Number.isInteger(change)) {
    throw new EngineError(
      'INVALID_SUSPICION_CHANGE',
      'Suspicion change must be an integer',
    );
  }

  const player = state.players[playerId];
  if (!player) {
    throw new EngineError('INVALID_PLAYER', `Unknown player: ${playerId}`);
  }

  const suspicion = Math.max(
    0,
    Math.min(MAX_SUSPICION, player.suspicion + change),
  );
  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    players: {
      ...state.players,
      [playerId]: { ...player, suspicion },
    },
  });
}

export function recordNoisyManipulation(
  state: MatchState,
  actorPlayerId: string,
): MatchState {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_ACTION_PHASE',
      'A noisy manipulation can only be recorded during the active_turn phase',
    );
  }

  if (state.currentPlayerId !== actorPlayerId) {
    throw new EngineError(
      'NOT_YOUR_TURN',
      'Only the current player may perform a noisy manipulation',
    );
  }

  const actor = state.players[actorPlayerId];
  if (!actor || actor.status !== 'active' || actor.hearts < 1) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'A noisy manipulation requires an Active player',
    );
  }

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    players: {
      ...state.players,
      [actorPlayerId]: {
        ...actor,
        suspicion: Math.min(MAX_SUSPICION, actor.suspicion + 1),
      },
    },
    publicActionHistory: [
      ...state.publicActionHistory,
      { playerId: actorPlayerId, kind: 'noisy_manipulation' },
    ],
  });
}

export function recordSuccessfulAttackDamage(
  state: MatchState,
  attackerPlayerId: string,
): MatchState {
  if (
    state.phase !== 'active_turn' &&
    state.phase !== 'awaiting_reaction' &&
    state.phase !== 'awaiting_accusation'
  ) {
    throw new EngineError(
      'INVALID_ACTION_PHASE',
      'Successful attack damage is not valid in the current phase',
    );
  }

  if (
    state.currentPlayerId !== attackerPlayerId ||
    state.attacksUsedThisTurn !== 1
  ) {
    throw new EngineError(
      'INVALID_ACTION_PHASE',
      "Successful attack damage must follow the current player's attack",
    );
  }

  const attacker = state.players[attackerPlayerId];
  if (!attacker || attacker.status !== 'active' || attacker.hearts < 1) {
    throw new EngineError(
      'NOT_ELIGIBLE',
      'Successful attack damage requires an Active attacker',
    );
  }

  if (state.suspicionAwardedForDamageThisTurn) {
    throw new EngineError(
      'DUPLICATE_ATTACK_RECORD',
      'Successful attack damage was already recorded this turn',
    );
  }

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    suspicionAwardedForDamageThisTurn: true,
    players: {
      ...state.players,
      [attackerPlayerId]: {
        ...attacker,
        suspicion: Math.min(MAX_SUSPICION, attacker.suspicion + 1),
      },
    },
    publicActionHistory: [
      ...state.publicActionHistory,
      { playerId: attackerPlayerId, kind: 'successful_attack' },
    ],
  });
}

export function hasBehaviorEvidenceQualifyingAction(
  state: MatchState,
  playerId: string,
): boolean {
  return state.publicActionHistory.some(
    (action) =>
      action.playerId === playerId &&
      (action.kind === 'successful_attack' ||
        action.kind === 'noisy_manipulation'),
  );
}
