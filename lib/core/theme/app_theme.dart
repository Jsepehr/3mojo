import 'package:flutter/material.dart';

/// Temi Material 3 per tutta l'app, chiaro e scuro, generati dallo stesso
/// colore seme — l'app segue il tema di sistema (`ThemeMode.system`).
class AppTheme {
  const AppTheme._();

  static const _seedColor = Color.fromARGB(255, 26, 60, 209);

  // Superfici scure blu (non il grigio quasi nero che Material 3 genera di
  // default dal seed) — stessa tonalità del seed, solo molto più scura.
  static const _darkSurfaceDim = Color(0xFF05080F);
  static const _darkSurface = Color(0xFF0B1220);
  static const _darkSurfaceBright = Color(0xFF29385A);
  static const _darkSurfaceContainerLowest = Color(0xFF05080F);
  static const _darkSurfaceContainerLow = Color(0xFF10192C);
  static const _darkSurfaceContainer = Color(0xFF152140);
  static const _darkSurfaceContainerHigh = Color(0xFF1F2E52);
  static const _darkSurfaceContainerHighest = Color(0xFF2A3C66);
  static const _darkOnSurface = Color(0xFFE3E7F5);
  static const _darkOnSurfaceVariant = Color(0xFFB9C2DD);
  static const _darkOutline = Color(0xFF5C6B94);
  static const _darkOutlineVariant = Color(0xFF3A4568);

  static ThemeData get light => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
    useMaterial3: true,
  );

  static ThemeData get dark {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ).copyWith(
          surfaceDim: _darkSurfaceDim,
          surface: _darkSurface,
          surfaceBright: _darkSurfaceBright,
          surfaceContainerLowest: _darkSurfaceContainerLowest,
          surfaceContainerLow: _darkSurfaceContainerLow,
          surfaceContainer: _darkSurfaceContainer,
          surfaceContainerHigh: _darkSurfaceContainerHigh,
          surfaceContainerHighest: _darkSurfaceContainerHighest,
          onSurface: _darkOnSurface,
          onSurfaceVariant: _darkOnSurfaceVariant,
          outline: _darkOutline,
          outlineVariant: _darkOutlineVariant,
          inverseSurface: _darkOnSurface,
          onInverseSurface: _darkSurfaceContainer,
        );

    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      useMaterial3: true,
    );
  }
}
