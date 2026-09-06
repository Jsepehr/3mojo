import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/chat_message.dart';

/// Un fumetto di chat, in stile WhatsApp: a destra ed evidenziato se è tuo,
/// a sinistra altrimenti, con un angolo "a coda" dalla parte del mittente
/// (raggio ridotto) e l'orario incorporato in fondo al testo — se il
/// messaggio è corto sta sulla stessa riga, altrimenti va a capo da solo,
/// perché è un [WidgetSpan] dentro lo stesso `Text.rich`, non una riga
/// separata.
class CmpChatMessageBubble extends StatelessWidget {
  const CmpChatMessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMine = message.isMine;
    final textColor = isMine ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeLabel = DateFormat.Hm(
      Localizations.localeOf(context).languageCode,
    ).format(message.sentAt);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        decoration: BoxDecoration(
          color: isMine ? colorScheme.primary : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: message.text, style: TextStyle(color: textColor)),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    timeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
