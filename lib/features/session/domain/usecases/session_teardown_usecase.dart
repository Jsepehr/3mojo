import 'package:fpdart/fpdart.dart';

import '/core/usecases/usecase.dart';

/// Contratto per un passo di pulizia che un'altra feature deve fare quando
/// la sessione finisce (End): smettere di essere visibili (`nearby`),
/// dimenticare le richieste (`encounters`), la chat (`chat`)... Il
/// parametro è l'id della sessione che sta finendo.
///
/// Esiste per tenere la dipendenza tra feature **a senso unico**: è
/// `session/` a definire il contratto e `EndSessionUseCase` a comporre i
/// passi senza conoscerli; le altre feature lo implementano (e dipendono
/// già da `session/` per sapere chi sono). Così `session/` non importa
/// nessuna di loro e non c'è un ciclo session ↔ nearby.
abstract class SessionTeardownUseCase implements UseCase<Unit, String> {}
