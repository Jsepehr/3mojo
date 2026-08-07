import 'package:equatable/equatable.dart';

abstract class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class CacheFailure extends Failure {
  const CacheFailure(super.message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure(super.message);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class LocationDisabledFailure extends Failure {
  const LocationDisabledFailure(super.message);
}

class LocationPermissionFailure extends Failure {
  const LocationPermissionFailure(super.message);
}
