import { matchStateSchema, type MatchState } from './state.js';
import type { RandomSource } from './random.js';
import { drawCardsFromPiles } from './deck.js';
import { EngineError } from './errors.js';

export const CARDS_PER_TURN = 2;
export const ACTIONS_PER_TURN = 2;
export const MAX_HAND_SIZE = 7;

export type TurnActionKind = 'attack' | 'action';

export function beginTurn(state: MatchState, random: RandomSource): MatchState {
  if (state.phase !== 'turn_start') {
    throw new Error(
      'A turn can begin drawing only during the turn_start phase',
    );
  }

  const currentPlayerId = state.currentPlayerId;
  if (currentPlayerId === null) {
    throw new Error('A current player is required to begin a turn');
  }

  const currentPlayer = state.players[currentPlayerId];
  if (!currentPlayer || currentPlayer.status !== 'active') {
    throw new Error('The current player must be Active to draw at turn start');
  }

  const { cards, drawPile, discardPile } = drawCardsFromPiles(
    state.drawPile,
    state.discardPile,
    CARDS_PER_TURN,
    random,
  );
  const players = {
    ...state.players,
    [currentPlayerId]: {
      ...currentPlayer,
      hand: [...currentPlayer.hand, ...cards],
    },
  };

  return matchStateSchema.parse({
    ...state,
    phase: 'active_turn',
    version: state.version + 1,
    actionsRemaining: ACTIONS_PER_TURN,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: [],
    players,
    drawPile,
    discardPile,
  });
}

export function spendAction(
  state: MatchState,
  kind: TurnActionKind,
  cost: 0 | 1 = 1,
): MatchState {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_PHASE',
      'An action can be spent only during the active_turn phase',
    );
  }

  if (kind !== 'attack' && kind !== 'action') {
    throw new EngineError(
      'INVALID_ACTION',
      `Unknown turn action kind: ${String(kind)}`,
    );
  }

  if (cost !== 0 && cost !== 1) {
    throw new EngineError(
      'INVALID_ACTION_COST',
      'Turn action cost must be 0 or 1',
    );
  }

  if (kind === 'attack' && cost !== 1) {
    throw new EngineError(
      'INVALID_ACTION_COST',
      'An attack must spend one action',
    );
  }

  if (kind === 'attack' && state.attacksUsedThisTurn >= 1) {
    throw new EngineError(
      'ATTACK_LIMIT',
      'Only one attack is allowed per turn',
    );
  }

  if (cost === 1 && state.actionsRemaining < 1) {
    throw new EngineError('NO_ACTIONS_REMAIN', 'No actions remain this turn');
  }

  return matchStateSchema.parse({
    ...state,
    version: state.version + 1,
    actionsRemaining: state.actionsRemaining - cost,
    attacksUsedThisTurn:
      state.attacksUsedThisTurn + (kind === 'attack' ? 1 : 0),
  });
}

export function endTurn(
  state: MatchState,
  cardInstanceIdsToDiscard: string[],
): MatchState {
  if (state.phase !== 'active_turn') {
    throw new EngineError(
      'INVALID_PHASE',
      'A turn can end only during the active_turn phase',
    );
  }

  const currentPlayerId = state.currentPlayerId;
  if (currentPlayerId === null || !state.seatOrder.includes(currentPlayerId)) {
    throw new Error('The active turn must belong to a player in seat order');
  }

  const currentPlayer = state.players[currentPlayerId];
  if (!currentPlayer || currentPlayer.status !== 'active') {
    throw new Error('The current player must be Active to end their turn');
  }

  const requiredDiscardCount = Math.max(
    0,
    currentPlayer.hand.length - MAX_HAND_SIZE,
  );
  if (cardInstanceIdsToDiscard.length !== requiredDiscardCount) {
    throw new EngineError(
      'INVALID_DISCARD_COUNT',
      `Discard exactly ${requiredDiscardCount} card(s) to end the turn`,
    );
  }

  if (
    new Set(cardInstanceIdsToDiscard).size !== cardInstanceIdsToDiscard.length
  ) {
    throw new EngineError(
      'INVALID_DISCARD',
      'Discarded card instance IDs must be unique',
    );
  }

  const hand = new Set(currentPlayer.hand);
  if (cardInstanceIdsToDiscard.some((cardId) => !hand.has(cardId))) {
    throw new EngineError(
      'INVALID_DISCARD',
      'Every discarded card must be in the current player hand',
    );
  }

  const discarded = new Set(cardInstanceIdsToDiscard);
  const players = {
    ...state.players,
    [currentPlayerId]: {
      ...currentPlayer,
      hand: currentPlayer.hand.filter((cardId) => !discarded.has(cardId)),
    },
  };
  const discardPile = [...state.discardPile, ...cardInstanceIdsToDiscard];
  const currentSeatIndex = state.seatOrder.indexOf(currentPlayerId);
  let nextPlayerId: string | null = null;
  let activeEffects = [...state.activeEffects];

  for (let offset = 1; offset <= state.seatOrder.length; offset += 1) {
    const candidateId =
      state.seatOrder[(currentSeatIndex + offset) % state.seatOrder.length];
    const candidate = players[candidateId];
    if (!candidate) {
      throw new Error(`Missing player state for seat ${candidateId}`);
    }

    if (candidate.status === 'eliminated') {
      continue;
    }

    activeEffects = activeEffects.filter(
      (effect) => effect.casterPlayerId !== candidateId,
    );

    if (candidate.status === 'cornered') {
      if (candidate.hearts !== 0) {
        throw new Error(`Cornered player ${candidateId} must have 0 Hearts`);
      }

      players[candidateId] = {
        ...candidate,
        status: 'active',
        hearts: 1,
      };
      continue;
    }

    if (candidate.hearts < 1) {
      throw new Error(
        `Active player ${candidateId} must have at least 1 Heart`,
      );
    }

    nextPlayerId = candidateId;
    break;
  }

  if (nextPlayerId === null) {
    throw new Error('No eligible player found to take the next turn');
  }

  return matchStateSchema.parse({
    ...state,
    phase: 'turn_start',
    version: state.version + 1,
    actionsRemaining: 0,
    attacksUsedThisTurn: 0,
    suspicionAwardedForDamageThisTurn: false,
    investigationTargetsThisTurn: [],
    currentPlayerId: nextPlayerId,
    players,
    discardPile,
    activeEffects,
  });
}
