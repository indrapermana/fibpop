import 'package:flutter/material.dart';

void main() {
  runApp(const FibpopApp());
}

class FibpopApp extends StatelessWidget {
  const FibpopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIBPOP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('FIBPOP\nM0 foundation', textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
