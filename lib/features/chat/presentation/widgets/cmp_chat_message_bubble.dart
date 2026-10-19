import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/chat_message.dart';

/// Un fumetto di chat, in stile WhatsApp: a destra ed evidenziato se è tuo,
/// a sinistra altrimenti, con un angolo "a coda" dalla parte del mittente
/// (raggio ridotto) e l'orario incorporato in fondo al testo — se il
/// messaggio è corto sta sulla stessa riga, altrimenti va a capo da solo,
/// perché è un [WidgetSpan] dentro lo stesso `Text.rich`, non una riga
/// separata.
///
/// Con [isUnsent] (il messaggio non è partito o non è stato consegnato) il
/// fumetto si attenua e sotto compare "Non inviato · Tocca per riprovare",
/// nel colore di errore: un tap chiama [onRetry].
class CmpChatMessageBubble extends StatelessWidget {
  const CmpChatMessageBubble({
    super.key,
    required this.message,
    this.isUnsent = false,
    this.onRetry,
  });

  final ChatMessage message;
  final bool isUnsent;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMine = message.isMine;
    final textColor = isMine ? colorScheme.onPrimary : colorScheme.onSurface;
    final timeLabel = DateFormat.Hm(
      Localizations.localeOf(context).languageCode,
    ).format(message.sentAt);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      decoration: BoxDecoration(
        color: isMine
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
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
            TextSpan(
              text: message.text,
              style: TextStyle(color: textColor),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!isUnsent) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubble,
      );
    }

    final l10n = AppLocalizations.of(context)!;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Opacity(opacity: 0.6, child: bubble),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 14, color: colorScheme.error),
                  const SizedBox(width: 4),
                  Text(
                    l10n.message_not_sent,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: colorScheme.error),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
