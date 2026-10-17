import 'package:flutter/material.dart';

/// Colori del brand che non hanno un ruolo adatto nel `ColorScheme` di
/// Material, letti dai widget con `RaenColors.of(context)` — mai hex nei widget.
///
/// - **heart**: il rosso del cuore dell'icona. È un accento *positivo* e raro
///   (richieste, "Sì", match, probabilità alta): sta qui e non in
///   `colorScheme.tertiary` apposta, così non finisce per caso nei componenti
///   che Material colora col terziario. Non va confuso con `colorScheme.error`
///   (End, errori): il cuore compare sempre col glifo ♥, l'errore mai.
/// - **heartDisc**: il cuore dentro il disco bianco, come nell'icona — uguale
///   in chiaro e scuro, perché il rosso direttamente sul blu non si legge (2.1:1).
/// - **hero**: lo sfondo blu pieno della home offline (`AppTheme.hero`).
/// - **photoScrim/onPhoto**: velo e icone sopra una foto, uguali nei due temi
///   perché dipendono dalla foto, non dallo sfondo dell'app.
@immutable
class RaenColors extends ThemeExtension<RaenColors> {
  const RaenColors({
    required this.heart,
    required this.onHeart,
    required this.heartContainer,
    required this.onHeartContainer,
    required this.heartDisc,
    required this.onHeartDisc,
    required this.hero,
    required this.onHero,
    required this.onHeroVariant,
    required this.photoScrim,
    required this.onPhoto,
  });

  final Color heart;
  final Color onHeart;
  final Color heartContainer;
  final Color onHeartContainer;
  final Color heartDisc;
  final Color onHeartDisc;
  final Color hero;
  final Color onHero;
  final Color onHeroVariant;
  final Color photoScrim;
  final Color onPhoto;

  static RaenColors of(BuildContext context) =>
      Theme.of(context).extension<RaenColors>()!;

  // Contrasti WCAG verificati: onHeart/heart 4.58, onHeartContainer/
  // heartContainer 9.22, onHeartDisc/heartDisc 4.58, onHero/hero 9.63.
  static const light = RaenColors(
    heart: Color(0xFFE3262E),
    onHeart: Color(0xFFFFFFFF),
    heartContainer: Color(0xFFFFE3E1),
    onHeartContainer: Color(0xFF7A0A12),
    heartDisc: Color(0xFFFFFFFF),
    onHeartDisc: Color(0xFFE3262E),
    hero: Color(0xFF0236B3),
    onHero: Color(0xFFFFFFFF),
    onHeroVariant: Color(0xFFDCE3FF),
    photoScrim: Color(0x66000000),
    onPhoto: Color(0xFFFFFFFF),
  );

  // Contrasti WCAG verificati: onHeart/heart 6.88, heart su surface 6.77,
  // onHeartContainer/heartContainer 10.80, onHero/hero 13.25.
  static const dark = RaenColors(
    heart: Color(0xFFFF6B72),
    onHeart: Color(0xFF2B0005),
    heartContainer: Color(0xFF5C0A12),
    onHeartContainer: Color(0xFFFFDAD9),
    heartDisc: Color(0xFFFFFFFF),
    onHeartDisc: Color(0xFFE3262E),
    hero: Color(0xFF01267F),
    onHero: Color(0xFFFFFFFF),
    onHeroVariant: Color(0xFFDCE3FF),
    photoScrim: Color(0x66000000),
    onPhoto: Color(0xFFFFFFFF),
  );

  @override
  RaenColors copyWith({
    Color? heart,
    Color? onHeart,
    Color? heartContainer,
    Color? onHeartContainer,
    Color? heartDisc,
    Color? onHeartDisc,
    Color? hero,
    Color? onHero,
    Color? onHeroVariant,
    Color? photoScrim,
    Color? onPhoto,
  }) {
    return RaenColors(
      heart: heart ?? this.heart,
      onHeart: onHeart ?? this.onHeart,
      heartContainer: heartContainer ?? this.heartContainer,
      onHeartContainer: onHeartContainer ?? this.onHeartContainer,
      heartDisc: heartDisc ?? this.heartDisc,
      onHeartDisc: onHeartDisc ?? this.onHeartDisc,
      hero: hero ?? this.hero,
      onHero: onHero ?? this.onHero,
      onHeroVariant: onHeroVariant ?? this.onHeroVariant,
      photoScrim: photoScrim ?? this.photoScrim,
      onPhoto: onPhoto ?? this.onPhoto,
    );
  }

  @override
  RaenColors lerp(RaenColors? other, double t) {
    if (other == null) return this;
    return RaenColors(
      heart: Color.lerp(heart, other.heart, t)!,
      onHeart: Color.lerp(onHeart, other.onHeart, t)!,
      heartContainer: Color.lerp(heartContainer, other.heartContainer, t)!,
      onHeartContainer: Color.lerp(
        onHeartContainer,
        other.onHeartContainer,
        t,
      )!,
      heartDisc: Color.lerp(heartDisc, other.heartDisc, t)!,
      onHeartDisc: Color.lerp(onHeartDisc, other.onHeartDisc, t)!,
      hero: Color.lerp(hero, other.hero, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      onHeroVariant: Color.lerp(onHeroVariant, other.onHeroVariant, t)!,
      photoScrim: Color.lerp(photoScrim, other.photoScrim, t)!,
      onPhoto: Color.lerp(onPhoto, other.onPhoto, t)!,
    );
  }
}
