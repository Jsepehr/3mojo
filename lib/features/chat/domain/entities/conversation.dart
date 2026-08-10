import 'package:equatable/equatable.dart';

/// La chat con una persona con cui hai fatto match. Dura finché nessuno
/// dei due la termina esplicitamente — nessuna scadenza a tempo.
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
