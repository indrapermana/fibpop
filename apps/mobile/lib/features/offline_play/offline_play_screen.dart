import 'package:flutter/material.dart';

class OfflinePlayScreen extends StatelessWidget {
  const OfflinePlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline play')),
      body: const Center(child: Text('Offline play is not available yet.')),
    );
  }
}
