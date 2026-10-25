import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '/features/session/domain/usecases/get_current_session_usecase.dart';

/// Azione: si può entrare nella **demo dichiarata**? Solo da offline — con
/// una sessione reale in corso le persone in "Vicinanze" sono vere, e la
/// demo (persone dimostrative, tutta sul telefono) non deve mai sovrapporsi
/// a loro né far credere di essere ancora visibili agli altri:
/// `DemoUnavailableDuringSessionFailure`. Compone `GetCurrentSessionUseCase`
/// della sessione **reale**.
class CheckDemoAvailableUseCase implements UseCase<Unit, NoParams> {
  const CheckDemoAvailableUseCase(this._getCurrentSessionUseCase);

  final GetCurrentSessionUseCase _getCurrentSessionUseCase;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) async {
    final result = await _getCurrentSessionUseCase(const NoParams());
    return result.flatMap(
      (session) => session == null
          ? const Right(unit)
          : const Left(DemoUnavailableDuringSessionFailure()),
    );
  }
}
