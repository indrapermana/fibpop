abstract interface class RandomSource {
  double next();
}

int randomIndex(int length, RandomSource random) {
  if (length < 1) {
    throw RangeError('Random index length must be a positive integer');
  }
  final value = random.next();
  if (!value.isFinite || value < 0 || value >= 1) {
    throw RangeError(
      'RandomSource.next() must return a finite value in [0, 1)',
    );
  }
  return (value * length).floor();
}

void shuffle<T>(List<T> items, RandomSource random) {
  for (var index = items.length - 1; index > 0; index--) {
    final other = randomIndex(index + 1, random);
    final value = items[index];
    items[index] = items[other];
    items[other] = value;
  }
}
