import { matchStateSchema, type MatchState } from './state.js';
import { shuffleInPlace, type RandomSource } from './random.js';

export const CARDS_PER_TURN = 2;
export const MAX_HAND_SIZE = 7;

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

  const drawPile = [...state.drawPile];
  let discardPile = [...state.discardPile];
  const players = {
    ...state.players,
    [currentPlayerId]: {
      ...currentPlayer,
      hand: [...currentPlayer.hand],
    },
  };

  for (let cardNumber = 0; cardNumber < CARDS_PER_TURN; cardNumber += 1) {
    if (drawPile.length === 0 && discardPile.length > 0) {
      drawPile.push(...shuffleInPlace(discardPile, random));
      discardPile = [];
    }

    const cardInstanceId = drawPile.pop();
    if (cardInstanceId === undefined) {
      break;
    }

    players[currentPlayerId].hand.push(cardInstanceId);
  }

  return matchStateSchema.parse({
    ...state,
    phase: 'active_turn',
    version: state.version + 1,
    players,
    drawPile,
    discardPile,
  });
}

export function endTurn(
  state: MatchState,
  cardInstanceIdsToDiscard: string[],
): MatchState {
  if (state.phase !== 'active_turn') {
    throw new Error('A turn can end only during the active_turn phase');
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
    throw new Error(
      `Discard exactly ${requiredDiscardCount} card(s) to end the turn`,
    );
  }

  if (
    new Set(cardInstanceIdsToDiscard).size !== cardInstanceIdsToDiscard.length
  ) {
    throw new Error('Discarded card instance IDs must be unique');
  }

  const hand = new Set(currentPlayer.hand);
  if (cardInstanceIdsToDiscard.some((cardId) => !hand.has(cardId))) {
    throw new Error('Every discarded card must be in the current player hand');
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
    currentPlayerId: nextPlayerId,
    players,
    discardPile,
  });
}
