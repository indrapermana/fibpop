import 'random.dart';

({List<String> cards, List<String> drawPile, List<String> discardPile})
drawCardsFromPiles(
  List<String> drawPile,
  List<String> discardPile,
  int count,
  RandomSource random,
) {
  if (count < 0) throw RangeError('Card draw count must be non-negative');
  final draw = [...drawPile];
  final discard = [...discardPile];
  final cards = <String>[];
  for (var i = 0; i < count; i++) {
    if (draw.isEmpty && discard.isNotEmpty) {
      shuffle(discard, random);
      draw.addAll(discard);
      discard.clear();
    }
    if (draw.isEmpty) break;
    cards.add(draw.removeLast());
  }
  return (cards: cards, drawPile: draw, discardPile: discard);
}
