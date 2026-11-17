import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/home/home_screen.dart';
import '../features/offline_play/offline_play_screen.dart';
import 'navigation/app_routes.dart';

class FibpopApp extends StatelessWidget {
  const FibpopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'FIBPOP',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        routes: {
          AppRoutes.home: (context) => const HomeScreen(),
          AppRoutes.offlinePlay: (context) => const OfflinePlayScreen(),
        },
      ),
    );
  }
}
