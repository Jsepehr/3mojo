import 'package:flutter/material.dart';

import '../../domain/entities/chat_message.dart';

/// Un fumetto di chat: a destra ed evidenziato se è tuo, a sinistra altrimenti.
class CmpChatMessageBubble extends StatelessWidget {
  const CmpChatMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMine
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isMine
                ? colorScheme.onPrimary
                : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
