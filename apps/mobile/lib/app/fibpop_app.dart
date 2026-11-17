import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import '../features/offline_play/offline_play_screen.dart';
import '../features/rules/card_guide_screen.dart';
import '../features/rules/rules_screen.dart';
import '../l10n/generated/app_localizations.dart';
import 'language_provider.dart';
import 'navigation/app_routes.dart';

class FibpopApp extends StatelessWidget {
  const FibpopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: const _App());
  }
}

class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: ref.watch(languageProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      routes: {
        AppRoutes.home: (context) => const HomeScreen(),
        AppRoutes.offlinePlay: (context) => const OfflinePlayScreen(),
        AppRoutes.rules: (context) => const RulesScreen(),
        AppRoutes.cards: (context) => const CardGuideScreen(),
      },
    );
  }
}
