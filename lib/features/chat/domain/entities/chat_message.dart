import 'package:equatable/equatable.dart';

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.isMine,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final bool isMine;
  final String text;
  final DateTime sentAt;

  @override
  List<Object?> get props => [id, isMine, text, sentAt];
}
