export interface RandomSource {
  next(): number;
}

function nextRandomValue(random: RandomSource): number {
  const value = random.next();
  if (!Number.isFinite(value) || value < 0 || value >= 1) {
    throw new RangeError(
      'RandomSource.next() must return a finite value in [0, 1)',
    );
  }

  return value;
}

export function shuffleInPlace<T>(items: T[], random: RandomSource): T[] {
  for (let index = items.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(nextRandomValue(random) * (index + 1));
    [items[index], items[swapIndex]] = [items[swapIndex], items[index]];
  }

  return items;
}

export function nextRandomIndex(length: number, random: RandomSource): number {
  if (!Number.isInteger(length) || length < 1) {
    throw new RangeError('Random index length must be a positive integer');
  }

  return Math.floor(nextRandomValue(random) * length);
}
