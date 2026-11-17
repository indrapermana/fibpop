import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';

class OfflinePlayScreen extends StatelessWidget {
  const OfflinePlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.offlinePlay)),
      body: Center(child: Text(strings.offlinePlayUnavailable)),
    );
  }
}
