import 'package:flutter/material.dart';

import '../../app/navigation/app_routes.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('FIBPOP\nM0 foundation', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.offlinePlay),
              child: const Text('Offline play'),
            ),
          ],
        ),
      ),
    );
  }
}
