import 'package:flutter/material.dart';

void main() {
  runApp(const CellkaApp());
}

class CellkaApp extends StatelessWidget {
  const CellkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cellka',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cellka')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Cellka: NetMonster/Cell Mapper alternative\n'
            'со спутниковыми картами Yandex MapKit.\n\n'
            'Экран карты и логика сбора данных о сотах '
            'находятся в разработке — см. docs/ARCHITECTURE.md',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
