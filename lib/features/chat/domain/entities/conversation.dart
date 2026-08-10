import 'package:equatable/equatable.dart';

class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.otherPersonId,
    required this.otherSelfiePath,
  });

  final String id;
  final String otherPersonId;
  final String otherSelfiePath;

  @override
  List<Object?> get props => [id, otherPersonId, otherSelfiePath];
}
