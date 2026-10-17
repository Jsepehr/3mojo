import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'raen_colors.dart';

/// Temi Material 3 per tutta l'app, chiaro e scuro — l'app segue il tema
/// scelto in Impostazioni (di default quello di sistema).
///
/// Colori presi dall'icona: blu del segnaposto `#0236B3` come primario,
/// rosso del cuore come accento raro (in `RaenColors`, non nel
/// `ColorScheme`), bianco. Il `ColorScheme` è scritto a mano e non generato
/// con `fromSeed`, che sposterebbe il blu verso un indaco spento.
/// Ogni coppia testo/sfondo rispetta WCAG AA (≥ 4.5:1, ≥ 3:1 per bordi e icone).
class AppTheme {
  const AppTheme._();

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0236B3),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDDE4FF),
    onPrimaryContainer: Color(0xFF001A5E),
    secondary: Color(0xFF4A5270),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE1E6F4),
    onSecondaryContainer: Color(0xFF10162B),
    // Terziario = blu profondo, non il rosso: il gradiente primario→terziario
    // (attesa in "Vicinanze") resta tutto nel blu del brand.
    tertiary: Color(0xFF001F70),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDDE4FF),
    onTertiaryContainer: Color(0xFF001A5E),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF10162B),
    onSurfaceVariant: Color(0xFF4A5270),
    surfaceDim: Color(0xFFD9DEEC),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF5F7FC),
    surfaceContainer: Color(0xFFEEF1F9),
    surfaceContainerHigh: Color(0xFFE8ECF6),
    surfaceContainerHighest: Color(0xFFE1E6F4),
    outline: Color(0xFF737A96),
    outlineVariant: Color(0xFFC6CBDD),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF252B40),
    onInverseSurface: Color(0xFFEEF1F9),
    inversePrimary: Color(0xFFB4C5FF),
    surfaceTint: Color(0xFF0236B3),
  );

  // Superfici scure blu notte (non il grigio quasi nero di Material 3).
  // Il blu del brand come testo su queste superfici non si legge (1.9:1):
  // il primario diventa un blu chiaro, e #0236B3 resta come container.
  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB4C5FF),
    onPrimary: Color(0xFF00227A),
    primaryContainer: Color(0xFF0236B3),
    onPrimaryContainer: Color(0xFFDCE3FF),
    secondary: Color(0xFFB9C2DD),
    onSecondary: Color(0xFF232B45),
    secondaryContainer: Color(0xFF3A4568),
    onSecondaryContainer: Color(0xFFDCE1F5),
    tertiary: Color(0xFF8FA8FF),
    onTertiary: Color(0xFF00227A),
    tertiaryContainer: Color(0xFF0236B3),
    onTertiaryContainer: Color(0xFFDCE3FF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF0B1220),
    onSurface: Color(0xFFE3E7F5),
    onSurfaceVariant: Color(0xFFB9C2DD),
    surfaceDim: Color(0xFF05080F),
    surfaceBright: Color(0xFF29385A),
    surfaceContainerLowest: Color(0xFF05080F),
    surfaceContainerLow: Color(0xFF10192C),
    surfaceContainer: Color(0xFF152140),
    surfaceContainerHigh: Color(0xFF1F2E52),
    surfaceContainerHighest: Color(0xFF2A3C66),
    outline: Color(0xFF5C6B94),
    outlineVariant: Color(0xFF3A4568),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE3E7F5),
    onInverseSurface: Color(0xFF152140),
    inversePrimary: Color(0xFF0236B3),
    surfaceTint: Color(0xFFB4C5FF),
  );

  static ThemeData get light => _build(_lightScheme, RaenColors.light);

  static ThemeData get dark => _build(_darkScheme, RaenColors.dark);

  /// Variante "hero" per la home offline: sfondo blu pieno del brand,
  /// testi e radar bianchi, Start come pillola bianca con testo blu.
  /// I widget restano gli stessi — cambiano solo i ruoli del tema
  /// (primary diventa il bianco, surface il blu).
  static ThemeData hero(ThemeData base) {
    final raen = base.extension<RaenColors>()!;
    final colorScheme = base.colorScheme.copyWith(
      primary: raen.onHero,
      onPrimary: raen.hero,
      surface: raen.hero,
      onSurface: raen.onHero,
      onSurfaceVariant: raen.onHeroVariant,
    );
    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: raen.hero,
      textTheme: _textTheme(colorScheme),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        foregroundColor: raen.onHero,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
    );
  }

  /// Manrope ovunque; titoli ExtraBold e un filo più stretti, etichette dei
  /// bottoni in grassetto — gerarchia data dal peso, come il segno pieno
  /// dell'icona.
  static TextTheme _textTheme(ColorScheme colorScheme) {
    final base = GoogleFonts.manropeTextTheme().apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );
    TextStyle? heavy(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5);
    TextStyle? bold(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w700);

    return base.copyWith(
      displayLarge: heavy(base.displayLarge),
      displayMedium: heavy(base.displayMedium),
      displaySmall: heavy(base.displaySmall),
      headlineLarge: heavy(base.headlineLarge),
      headlineMedium: heavy(base.headlineMedium),
      headlineSmall: heavy(base.headlineSmall),
      titleLarge: heavy(base.titleLarge),
      titleMedium: bold(base.titleMedium),
      labelLarge: bold(base.labelLarge),
    );
  }

  static ThemeData _build(ColorScheme colorScheme, RaenColors raen) {
    final textTheme = _textTheme(colorScheme);
    const pill = StadiumBorder();
    const buttonSize = Size(64, 52);
    // Card bianche su fondo bianco in chiaro (staccate dal bordo), appena più
    // chiare del fondo in scuro.
    final cardColor = colorScheme.brightness == Brightness.light
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainerLow;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [raen],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: colorScheme.surface),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          minimumSize: buttonSize,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          minimumSize: buttonSize,
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: colorScheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          textStyle: textTheme.labelLarge,
        ),
      ),
      // Il Badge di Material usa `error` di default: qui le richieste in
      // arrivo sono una buona notizia, quindi rosso-cuore, non rosso-errore.
      badgeTheme: BadgeThemeData(
        backgroundColor: raen.heart,
        textColor: raen.onHeart,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(titleTextStyle: textTheme.headlineSmall),
    );
  }
}
