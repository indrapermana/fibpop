import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/features/rules/card_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('both UI languages contain the same nonempty messages', () async {
    final en =
        jsonDecode(await File('lib/l10n/app_en.arb').readAsString())
            as Map<String, dynamic>;
    final id =
        jsonDecode(await File('lib/l10n/app_id.arb').readAsString())
            as Map<String, dynamic>;
    final keys = en.keys.where((key) => !key.startsWith('@')).toSet();
    expect(id.keys.where((key) => !key.startsWith('@')).toSet(), keys);
    for (final key in keys) {
      expect(en[key], isA<String>());
      expect(id[key], isA<String>());
      expect((en[key] as String).trim(), isNotEmpty, reason: key);
      expect((id[key] as String).trim(), isNotEmpty, reason: key);
    }
  });

  test(
    'card translations cover the source catalog and Indonesian rulebook',
    () async {
      final cards = parseCardText(
        await rootBundle.loadString('assets/card_text.json'),
      );
      final catalog =
          jsonDecode(
                await File('../../shared/card_catalog_v1.json').readAsString(),
              )
              as Map<String, dynamic>;
      final source = (catalog['cards'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final rulebook = await File(
        '../../game-rules/Original_Game_Rules_ID.md',
      ).readAsString();
      final rows = RegExp(
        r'^\| \*\*(.*?) \((.*?)\)\*\* \| \d+ \| (.*?) \|$',
        multiLine: true,
      ).allMatches(rulebook);
      final indonesian = {
        for (final row in rows)
          row.group(1)!: (row.group(2)!, row.group(3)!.replaceAll('**', '')),
      };

      expect(
        cards.map((card) => card.id).toSet(),
        source.map((card) => card['id']).toSet(),
      );
      expect(indonesian.length, 24);
      for (final sourceCard in source) {
        final card = cards.singleWhere((card) => card.id == sourceCard['id']);
        expect(card.en.name, sourceCard['name_en'], reason: card.id);
        expect(card.en.text, sourceCard['rules_text_en'], reason: card.id);
        final translation = indonesian[card.en.name];
        expect(translation, isNotNull, reason: card.id);
        expect(card.idText.name, translation!.$1, reason: card.id);
        expect(card.idText.text, translation.$2, reason: card.id);
      }
    },
  );

  test('rejects missing card translations and unsupported languages', () {
    expect(
      () => parseCardText('{"card_01":{"en":{"name":"A","text":"B"}}}'),
      throwsFormatException,
    );
    final card = parseCardText(
      '{"card_01":{"en":{"name":"A","text":"B"},"id":{"name":"C","text":"D"}}}',
    ).single;
    expect(() => card.forLanguage('fr'), throwsArgumentError);
  });
}
