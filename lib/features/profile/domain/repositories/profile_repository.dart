import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../entities/profile.dart';

abstract class ProfileRepository {
  Future<Either<Failure, Profile>> getMyProfile();
  Future<Either<Failure, Profile>> updateProfile(Profile profile);
}
