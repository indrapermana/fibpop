import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import 'card_text.dart';

class CardGuideScreen extends ConsumerWidget {
  const CardGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final cards = ref.watch(cardTextProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.cardGuide)),
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            Center(child: Text(strings.contentLoadError)),
        data: (cards) => ListView.builder(
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final text = cards[index].forLanguage(language);
            return ListTile(
              title: Text(text.name),
              subtitle: Text(text.text.replaceAll('**', '')),
            );
          },
        ),
      ),
    );
  }
}
