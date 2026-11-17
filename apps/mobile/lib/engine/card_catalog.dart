const catalogVersion = '1.0.0';

class CardDesign {
  const CardDesign({required this.id, required this.copies});

  final String id;
  final int copies;
}

class CardCatalog {
  CardCatalog._(List<CardDesign> cards) : cards = List.unmodifiable(cards);

  final List<CardDesign> cards;

  factory CardCatalog.fromJson(Map<String, Object?> json) {
    if (json.keys.toSet().difference({
          'catalog_version',
          'source',
          'status',
          'cards',
        }).isNotEmpty ||
        json['source'] is! String ||
        (json['source'] as String).isEmpty ||
        json['status'] is! String ||
        (json['status'] as String).isEmpty) {
      throw const FormatException('Invalid card catalog');
    }
    if (json['catalog_version'] != catalogVersion) {
      throw const FormatException('Unsupported card catalog version');
    }
    final source = json['cards'];
    if (source is! List || source.length != 24) {
      throw const FormatException('Card catalog must contain 24 designs');
    }
    final cards = <CardDesign>[];
    final seen = <String>{};
    var total = 0;
    for (final item in source) {
      if (item is! Map ||
          item['id'] is! String ||
          item['copies'] is! int ||
          item.keys.toSet().difference({
            'id',
            'category',
            'name_en',
            'copies',
            'rules_text_en',
          }).isNotEmpty ||
          !{
            'attacks',
            'defense',
            'investigation',
            'manipulation',
            'recovery',
            'special',
          }.contains(item['category']) ||
          item['name_en'] is! String ||
          (item['name_en'] as String).isEmpty ||
          item['rules_text_en'] is! String ||
          (item['rules_text_en'] as String).isEmpty) {
        throw const FormatException('Invalid card design');
      }
      final id = item['id'] as String;
      final copies = item['copies'] as int;
      if (!RegExp(r'^card_\d{2}$').hasMatch(id) ||
          copies < 1 ||
          !seen.add(id)) {
        throw FormatException('Invalid or duplicate card design: $id');
      }
      total += copies;
      cards.add(CardDesign(id: id, copies: copies));
    }
    if (total != 72) {
      throw const FormatException('Card catalog must contain 72 copies');
    }
    return CardCatalog._(cards);
  }
}
