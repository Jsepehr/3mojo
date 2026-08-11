import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';

/// Contratto per verificare che una foto contenga almeno un volto — non
/// riconosce **chi** sia (nessuna identità, nessun dato biometrico salvato),
/// solo che ci sia una faccia e non, per dire, un paesaggio o un logo.
abstract class FaceDetectionRepository {
  Future<Either<Failure, bool>> containsFace(String imagePath);
}
