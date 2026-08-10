import 'package:flutter/material.dart';

/// Tema Material 3 unico per tutta l'app, generato da un solo colore seme.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color.fromARGB(255, 26, 60, 209),
    ),
    useMaterial3: true,
  );
}
