import 'package:flutter/material.dart';

import 'features/map_screen/map_screen.dart';

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
      themeMode: ThemeMode.dark, // тёмная тема по умолчанию (см. DESIGN.md)
      home: const MapScreen(),
    );
  }
}
