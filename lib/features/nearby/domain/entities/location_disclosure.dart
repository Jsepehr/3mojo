import 'package:equatable/equatable.dart';

/// L'avviso in evidenza da mostrare **prima** della richiesta del permesso
/// di posizione (politica "Dati utente" di Google Play, "prominent
/// disclosure"): cosa si fa della posizione e fino a quando. Esiste solo
/// finché il permesso non è concesso (vedi `GetLocationDisclosureUseCase`).
///
/// I testi stanno negli ARB; qui solo il fatto che li rende **veri per
/// piattaforma**: [continuesInBackground] dice se, mentre si è online, la
/// posizione continua a essere usata anche con l'app in background o lo
/// schermo spento (Android, foreground service con notifica fissa) oppure
/// solo con l'app aperta sullo schermo (iOS: niente `UIBackgroundModes`
/// `location` in `Info.plist`).
class LocationDisclosure extends Equatable {
  const LocationDisclosure({required this.continuesInBackground});

  final bool continuesInBackground;

  @override
  List<Object?> get props => [continuesInBackground];
}
