export function getCardDesignId(cardInstanceId: string): string | null {
  return /^(card_\d{2}):[1-9]\d*$/.exec(cardInstanceId)?.[1] ?? null;
}
