import { parseCardCatalog, type CardCatalog } from './card-catalog.js';
import {
  nextRandomIndex,
  shuffleInPlace,
  type RandomSource,
} from './random.js';
import {
  CATALOG_VERSION,
  matchStateSchema,
  RULES_VERSION,
  type MatchState,
  type PlayerRole,
  type PlayerState,
} from './state.js';

export const MIN_PLAYERS = 4;
export const MAX_PLAYERS = 8;
export const STARTING_HEARTS = 3;
export const STARTING_HAND_SIZE = 4;

export interface CreateMatchInput {
  matchId: string;
  playerIds: string[];
  catalog: unknown;
  random: RandomSource;
}

function createCardInstanceIds(catalog: CardCatalog): string[] {
  return catalog.cards.flatMap((card) =>
    Array.from(
      { length: card.copies },
      (_, index) => `${card.id}:${index + 1}`,
    ),
  );
}

export function createMatch(input: CreateMatchInput): MatchState {
  if (
    !input.matchId.trim() ||
    input.playerIds.some((playerId) => !playerId.trim()) ||
    input.playerIds.length < MIN_PLAYERS ||
    input.playerIds.length > MAX_PLAYERS ||
    new Set(input.playerIds).size !== input.playerIds.length
  ) {
    throw new Error('Match requires a non-empty ID and 4–8 unique player IDs');
  }

  const catalog = parseCardCatalog(input.catalog);
  if (catalog.catalog_version !== CATALOG_VERSION) {
    throw new Error(
      `Unsupported card catalog version: ${catalog.catalog_version}`,
    );
  }

  const roleDeck: PlayerRole[] = [
    'impostor',
    ...Array.from(
      { length: input.playerIds.length - 1 },
      (): PlayerRole => 'innocent',
    ),
  ];
  shuffleInPlace(roleDeck, input.random);

  const drawPile = shuffleInPlace(createCardInstanceIds(catalog), input.random);
  const players: Record<string, PlayerState> = {};
  input.playerIds.forEach((playerId, index) => {
    players[playerId] = {
      playerId,
      role: roleDeck[index],
      status: 'active',
      hearts: STARTING_HEARTS,
      suspicion: 0,
      hand: [],
      evidence: {},
      accusationUsed: false,
    };
  });

  for (const playerId of input.playerIds) {
    for (let cardNumber = 0; cardNumber < STARTING_HAND_SIZE; cardNumber += 1) {
      const cardInstanceId = drawPile.pop();
      if (cardInstanceId === undefined) {
        throw new Error('Not enough cards to deal the starting hands');
      }

      players[playerId].hand.push(cardInstanceId);
    }
  }

  const currentPlayerId =
    input.playerIds[nextRandomIndex(input.playerIds.length, input.random)];

  return matchStateSchema.parse({
    matchId: input.matchId,
    rulesVersion: RULES_VERSION,
    catalogVersion: CATALOG_VERSION,
    phase: 'turn_start',
    version: 0,
    currentPlayerId,
    seatOrder: [...input.playerIds],
    deadlineUtc: null,
    players,
    drawPile,
    discardPile: [],
    activeEffects: [],
    accusationUsed: [],
    winner: null,
  });
}
