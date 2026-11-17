import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fibpop_mobile/app/fibpop_app.dart';
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
    await tester.pumpWidget(const FibpopApp());

    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });

  testWidgets('navigates to the offline play placeholder and back', (
    tester,
  ) async {
    await tester.pumpWidget(const FibpopApp());

    await tester.tap(find.text('Offline play'));
    await tester.pumpAndSettle();
    expect(find.text('Offline play is not available yet.'), findsOneWidget);
    expect(find.text('FIBPOP\nM0 foundation'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('FIBPOP\nM0 foundation'), findsOneWidget);
  });

  testWidgets('changes language for screens, rules and card descriptions', (
    tester,
  ) async {
    await tester.pumpWidget(const FibpopApp());
    await tester.tap(find.text('How to play'));
    await tester.pumpAndSettle();
    expect(find.text('Goal and setup'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Card guide'));
    await tester.pumpAndSettle();
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
    await tester.pumpAndSettle();
    expect(find.text('Permainan offline belum tersedia.'), findsOneWidget);
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
    await tester.pumpWidget(const FibpopApp());
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
