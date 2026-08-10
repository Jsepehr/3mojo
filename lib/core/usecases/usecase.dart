import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../errors/failures.dart';

/// Contratto comune a ogni use case dell'app: una singola azione di
/// business che prende `Params` e ritorna `Result`, o un `Failure` se
/// qualcosa va storto. Ogni feature implementa questa interfaccia per
/// le proprie azioni (es. `GetNearbyPeopleUseCase`, `SendMessageUseCase`).
abstract class UseCase<Result, Params> {
  Future<Either<Failure, Result>> call(Params params);
}

/// Segnaposto per gli use case che non hanno bisogno di parametri in ingresso.
class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => [];
}
