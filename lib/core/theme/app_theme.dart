import 'package:flutter/material.dart';

/// Temi Material 3 per tutta l'app, chiaro e scuro, generati dallo stesso
/// colore seme — l'app segue il tema di sistema (`ThemeMode.system`).
class AppTheme {
  const AppTheme._();

  static const _seedColor = Color.fromARGB(255, 26, 60, 209);

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
  );

  static ThemeData get dark => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
