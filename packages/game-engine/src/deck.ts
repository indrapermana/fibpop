import { shuffleInPlace, type RandomSource } from './random.js';

export interface DrawCardsResult {
  cards: string[];
  drawPile: string[];
  discardPile: string[];
}

export function drawCardsFromPiles(
  drawPileInput: string[],
  discardPileInput: string[],
  count: number,
  random: RandomSource,
): DrawCardsResult {
  if (!Number.isInteger(count) || count < 0) {
    throw new RangeError('Card draw count must be a non-negative integer');
  }

  const drawPile = [...drawPileInput];
  let discardPile = [...discardPileInput];
  const cards: string[] = [];

  for (let cardNumber = 0; cardNumber < count; cardNumber += 1) {
    if (drawPile.length === 0 && discardPile.length > 0) {
      drawPile.push(...shuffleInPlace(discardPile, random));
      discardPile = [];
    }

    const cardInstanceId = drawPile.pop();
    if (cardInstanceId === undefined) {
      break;
    }

    cards.push(cardInstanceId);
  }

  return { cards, drawPile, discardPile };
}
