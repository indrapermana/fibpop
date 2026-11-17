import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final sections = [
      (strings.rulesOverviewTitle, strings.rulesOverview),
      (strings.rulesTurnTitle, strings.rulesTurn),
      (strings.rulesEvidenceTitle, strings.rulesEvidence),
      (strings.rulesAttackTitle, strings.rulesAttack),
      (strings.rulesCorneredTitle, strings.rulesCornered),
      (strings.rulesVictoryTitle, strings.rulesVictory),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(strings.rulesHelp)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (title, text) in sections) ...[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
