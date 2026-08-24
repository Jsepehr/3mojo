import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/utils/photo_data_uri.dart';
import '/features/chat/presentation/providers/pro_chat.dart';
import '/features/chat/presentation/widgets/cmp_chat_message_bubble.dart';
import '/features/encounters/domain/entities/encounter_request.dart';
import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/l10n/generated/app_localizations.dart';

/// Pagina a schermo intero per il match attivo: chat con la persona,
/// apre da sola (vedi `_MatchGate` in app.dart) e blocca l'uscita
/// (tasto indietro o bottone "Termina") dietro una conferma, perché
/// uscire termina per sempre il match.
class UiActiveMatch extends StatefulWidget {
  const UiActiveMatch({super.key, required this.request});

  final EncounterRequest request;

  @override
  State<UiActiveMatch> createState() => _UiActiveMatchState();
}

class _UiActiveMatchState extends State<UiActiveMatch> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<ProChat>().open(
      otherPersonId: widget.request.otherPersonId,
      otherSelfiePath: widget.request.otherSelfiePath,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    context.read<ProChat>().sendMessage(text);
    _textController.clear();
  }

  Future<bool> _confirmLeave(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.matchLeaveWarningTitle),
        content: Text(l10n.matchLeaveWarningMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.matchLeaveWarningCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.matchLeaveWarningConfirm),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _leaveMatch(AppLocalizations l10n) async {
    final confirmed = await _confirmLeave(l10n);
    if (!confirmed || !mounted) return;

    await context.read<ProEncounters>().endMatch(widget.request.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proChat = context.watch<ProChat>();
    final photo = imageProviderForPhoto(widget.request.otherSelfiePath);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveMatch(l10n);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: photo,
                child: photo == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Text(l10n.chatPageTitle),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => _leaveMatch(l10n),
              child: Text(l10n.matchEndButton),
            ),
          ],
        ),
        body: proChat.isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: proChat.messages.length,
                      itemBuilder: (context, index) {
                        final message = proChat
                            .messages[proChat.messages.length - 1 - index];
                        return CmpChatMessageBubble(message: message);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            decoration: InputDecoration(
                              hintText: l10n.chatInputHint,
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _send,
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
