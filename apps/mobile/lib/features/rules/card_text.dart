import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocalizedCardText {
  const LocalizedCardText({required this.name, required this.text});

  final String name;
  final String text;
}

class CardText {
  const CardText({required this.id, required this.en, required this.idText});

  final String id;
  final LocalizedCardText en;
  final LocalizedCardText idText;

  LocalizedCardText forLanguage(String languageCode) => switch (languageCode) {
    'en' => en,
    'id' => idText,
    _ => throw ArgumentError.value(
      languageCode,
      'languageCode',
      'Unsupported language',
    ),
  };
}

LocalizedCardText _parseTranslation(
  Object? value,
  String cardId,
  String language,
) {
  if (value is! Map<String, dynamic> ||
      value['name'] is! String ||
      value['text'] is! String ||
      (value['name'] as String).trim().isEmpty ||
      (value['text'] as String).trim().isEmpty) {
    throw FormatException('Invalid $language card text for $cardId');
  }
  return LocalizedCardText(
    name: value['name'] as String,
    text: value['text'] as String,
  );
}

List<CardText> parseCardText(String json) {
  final Object? decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Card text must be an object');
  }
  final cards = <CardText>[];
  for (final entry in decoded.entries) {
    final value = entry.value;
    if (!RegExp(r'^card_\d{2}$').hasMatch(entry.key) ||
        value is! Map<String, dynamic>) {
      throw FormatException('Invalid card text entry: ${entry.key}');
    }
    cards.add(
      CardText(
        id: entry.key,
        en: _parseTranslation(value['en'], entry.key, 'en'),
        idText: _parseTranslation(value['id'], entry.key, 'id'),
      ),
    );
  }
  if (cards.isEmpty) throw const FormatException('Card text is empty');
  cards.sort((a, b) => a.id.compareTo(b.id));
  return List.unmodifiable(cards);
}

final cardTextProvider = FutureProvider<List<CardText>>((ref) async {
  final json = await rootBundle.loadString('assets/card_text.json');
  return parseCardText(json);
});
