import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/app/fibpop_app.dart';
import 'package:fibpop_mobile/engine/card_catalog.dart';
import 'package:fibpop_mobile/features/offline_play/card_catalog_provider.dart';
import 'package:fibpop_mobile/features/rules/card_guide_screen.dart';
import 'package:fibpop_mobile/features/rules/card_text.dart';
import 'package:fibpop_mobile/l10n/generated/app_localizations.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = [
      const Locale('en'),
    ];
  });
  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher
        .clearLocalesTestValue();
  });

  testWidgets('shows the FIBPOP M0 landing screen', (tester) async {
    await tester.pumpWidget(_appWithLoadedContent());

    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });

  testWidgets('starts an offline match and renders the private player hand', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithLoadedContent());

    await tester.tap(find.text('Offline play'));
    await _pumpUntil(tester, find.text('Start match'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Start a local match'), findsOneWidget);
    expect(find.text('Players'), findsOneWidget);
    expect(find.text('FIBPOP\nM0 foundation'), findsNothing);

    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();
    expect(find.text('Player 1'), findsWidgets);
    expect(find.byKey(const Key('offline-private-role')), findsNothing);
    await tester.tap(find.text('Reveal my role'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline-private-role')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Your hand'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Your hand'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });

  testWidgets('supports an eight-player table and clockwise turn cycling', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithLoadedContent());
    await tester.tap(find.text('Offline play'));
    await _pumpUntil(tester, find.text('Start match'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();

    final currentTurn = tester.widget<Text>(
      find.textContaining('Current turn: Player'),
    );
    final playerNumber = int.parse(
      RegExp(r'Player (\d+)').firstMatch(currentTurn.data!)!.group(1)!,
    );
    await tester.scrollUntilVisible(
      find.text('Player 8'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Player 8'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('End turn'),
      250,
      scrollable: find.byType(Scrollable).last,
    );

    await tester.tap(find.text('End turn'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 1000));
    await tester.pumpAndSettle();

    expect(
      find.text('Current turn: Player ${(playerNumber % 8) + 1}'),
      findsOneWidget,
    );
    expect(find.text('Actions remaining: 2'), findsOneWidget);
  });

  testWidgets('changes language for screens, rules and card descriptions', (
    tester,
  ) async {
    await tester.pumpWidget(_appWithLoadedContent());
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('Goal and setup'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Card guide'));
    await _pumpUntil(tester, find.text('Pressure!'));
    expect(find.text('Pressure!'), findsOneWidget);
    expect(
      find.text('Attack; deal 1 Heart of damage unless blocked.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Device language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahasa Indonesia').last);
    await tester.pumpAndSettle();
    expect(find.text('Bahasa'), findsOneWidget);
    expect(find.text('Main offline'), findsOneWidget);

    await tester.tap(find.text('Cara bermain'));
    await tester.pumpAndSettle();
    expect(find.text('Tujuan dan persiapan'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Panduan kartu'));
    await tester.pumpAndSettle();
    expect(find.text('Tekan!'), findsOneWidget);
    expect(
      find.text('Menyerang; memberi 1 luka jika tidak ditahan.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Main offline'));
    await _pumpUntil(tester, find.text('Mulai permainan'));
    expect(find.text('Mulai permainan lokal'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahasa Indonesia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bahasa perangkat').last);
    await tester.pumpAndSettle();
    expect(find.text('Offline play'), findsOneWidget);
  });

  testWidgets('uses the device language when no override is selected', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('id')];
    await tester.pumpWidget(_appWithLoadedContent());
    await tester.pumpAndSettle();
    expect(find.text('Main offline'), findsOneWidget);
    expect(find.text('Bahasa perangkat'), findsOneWidget);
  });

  testWidgets('shows an error when card descriptions cannot be loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardTextProvider.overrideWith(
            (ref) async => throw StateError('unavailable'),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: CardGuideScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Card descriptions could not be loaded.'), findsOneWidget);
  });
}

Widget _appWithLoadedContent() => ProviderScope(
  overrides: [
    cardTextProvider.overrideWith(
      (ref) async =>
          parseCardText(File('assets/card_text.json').readAsStringSync()),
    ),
    offlineCardCatalogProvider.overrideWith((ref) async {
      final decoded = jsonDecode(
        File('../../shared/card_catalog_v1.json').readAsStringSync(),
      );
      if (decoded is! Map) {
        throw const FormatException('Card catalog must be an object');
      }
      return CardCatalog.fromJson(decoded.cast<String, Object?>());
    }),
  ],
  child: const FibpopApp(),
);

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .whereType<String>()
      .join(' | ');
  fail('Timed out waiting for $finder. Current text: $visibleText');
}
