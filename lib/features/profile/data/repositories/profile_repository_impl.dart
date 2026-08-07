import 'package:fpdart/fpdart.dart';

import '/core/errors/failures.dart';
import '../../domain/entities/profile.dart';
import '../../domain/repositories/profile_repository.dart';
import '../datasources/profile_local_data_source.dart';
import '../models/profile_model.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._localDataSource);

  final ProfileLocalDataSource _localDataSource;

  @override
  Future<Either<Failure, Profile>> getMyProfile() async {
    try {
      return Right(await _localDataSource.getMyProfile());
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Profile>> updateProfile(Profile profile) async {
    try {
      final model = ProfileModel.fromEntity(profile);
      return Right(await _localDataSource.updateProfile(model));
    } catch (e) {
      return Left(UnexpectedFailure(e.toString()));
    }
  }
}
