import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/language_provider.dart';
import '../../app/navigation/app_routes.dart';
import '../../l10n/generated/app_localizations.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.foundation, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.offlinePlay),
                child: Text(strings.offlinePlay),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.rules),
                child: Text(strings.rulesHelp),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.cards),
                child: Text(strings.cardGuide),
              ),
              const SizedBox(height: 16),
              Text(strings.language),
              Semantics(
                label: strings.language,
                child: DropdownButton<Locale?>(
                  value: ref.watch(languageProvider),
                  onChanged: (locale) =>
                      ref.read(languageProvider.notifier).state = locale,
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(strings.systemLanguage),
                    ),
                    const DropdownMenuItem(
                      value: Locale('en'),
                      child: Text('English'),
                    ),
                    const DropdownMenuItem(
                      value: Locale('id'),
                      child: Text('Bahasa Indonesia'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
