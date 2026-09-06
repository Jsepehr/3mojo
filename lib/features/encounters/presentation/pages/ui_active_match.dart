import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_loading_indicator.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/chat/presentation/providers/pro_chat.dart';
import '/features/chat/presentation/widgets/cmp_chat_message_bubble.dart';
import '/features/encounters/domain/entities/encounter_request.dart';
import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/l10n/generated/app_localizations.dart';

/// Altezza del pannello emoji (stile WhatsApp: sostituisce la tastiera,
/// non si sovrappone).
const _emojiPickerHeight = 256.0;

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
  final FocusNode _textFieldFocusNode = FocusNode();
  bool _showEmojiPicker = false;

  @override
  void initState() {
    super.initState();
    context.read<ProChat>().open(
      otherPersonId: widget.request.otherPersonId,
      otherSelfiePath: widget.request.otherSelfiePath,
    );
    // Se l'utente tocca di nuovo il campo mentre il pannello emoji è aperto,
    // si comporta come WhatsApp: torna la tastiera, sparisce il pannello.
    _textFieldFocusNode.addListener(() {
      if (_textFieldFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFieldFocusNode.dispose();
    super.dispose();
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _textFieldFocusNode.requestFocus();
    } else {
      _textFieldFocusNode.unfocus();
      setState(() => _showEmojiPicker = true);
    }
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

    context.read<ProEncounters>().endMatch(
      requestId: widget.request.id,
      otherPersonId: widget.request.otherPersonId,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
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
              CmpPhoto(image: photo, size: 40),
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
            ? const Center(child: CmpLoadingIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Container(
                      // Sfondo appena tinto per staccare l'area dei
                      // messaggi dall'AppBar/barra di composizione, come lo
                      // sfondo distinto (per noi tinto, non un motivo grafico
                      // preso da un'altra app) dietro le chat di WhatsApp.
                      color: Color.alphaBlend(
                        colorScheme.primary.withValues(alpha: 0.05),
                        colorScheme.surface,
                      ),
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
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(
                                minHeight: 48,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _textController,
                                focusNode: _textFieldFocusNode,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: l10n.chatInputHint,
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  prefixIcon: IconButton(
                                    icon: Icon(
                                      _showEmojiPicker
                                          ? Icons.keyboard
                                          : Icons.emoji_emotions_outlined,
                                    ),
                                    onPressed: _toggleEmojiPicker,
                                  ),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                            ),
                            icon: const Icon(Icons.send),
                            onPressed: _send,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: !_showEmojiPicker,
                    child: SizedBox(
                      height: _emojiPickerHeight,
                      child: EmojiPicker(
                        textEditingController: _textController,
                        config: Config(
                          height: _emojiPickerHeight,
                          emojiViewConfig: EmojiViewConfig(
                            backgroundColor: colorScheme.surfaceContainerLow,
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            backgroundColor: colorScheme.surfaceContainerLow,
                            indicatorColor: colorScheme.primary,
                            iconColorSelected: colorScheme.primary,
                            backspaceColor: colorScheme.primary,
                          ),
                          bottomActionBarConfig: BottomActionBarConfig(
                            backgroundColor: colorScheme.surfaceContainerLow,
                            buttonColor: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
