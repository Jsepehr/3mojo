import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '/core/usecases/usecase.dart';
import '../entities/unlock_offer.dart';
import '../repositories/store_repository.dart';

/// Azione: lo sblocco si può comprare, e a quanto? Il prezzo è quello del
/// negozio (formattato da lui), mai uno scritto nell'app — tranne col
/// negozio simulato. `StoreUnavailableFailure` = il bottone dice "Non
/// disponibile" e il pagamento non parte.
class GetUnlockOfferUseCase implements UseCase<UnlockOffer, NoParams> {
  const GetUnlockOfferUseCase(this._storeRepository);

  final StoreRepository _storeRepository;

  @override
  Future<Either<Failure, UnlockOffer>> call(NoParams params) =>
      _storeRepository.getUnlockOffer();
}
