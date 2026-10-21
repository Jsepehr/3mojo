import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/core/errors/failures.dart';
import '/core/theme/raen_colors.dart';
import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_end_button.dart';
import '/core/widgets/cmp_inline_error.dart';
import '/core/widgets/cmp_loading_indicator.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/chat/domain/usecases/send_message_usecase.dart';
import '/features/chat/presentation/providers/pro_chat.dart';
import '/features/chat/presentation/widgets/cmp_chat_message_bubble.dart';
import '/features/encounters/domain/entities/encounter_proposal.dart';
import '/features/encounters/domain/entities/encounter_request.dart';
import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/features/session/presentation/widgets/cmp_connection_banner.dart';
import '/l10n/generated/app_localizations.dart';
import '../encounter_proposal_labels.dart';

/// Altezza del pannello emoji (stile WhatsApp: sostituisce la tastiera,
/// non si sovrappone).
const _emojiPickerHeight = 256.0;

/// Pagina a schermo intero per il match attivo: chat con la persona,
/// apre da sola (vedi `CmpMatchGate`) e blocca l'uscita
/// (tasto indietro o bottone "Termina") dietro una conferma, perché
/// uscire termina per sempre il match. Se il match finisce in un altro
/// modo (l'altra persona esce, la sessione finisce) è `CmpMatchGate` a
/// chiuderla.
///
/// Finché non c'è ancora nessun messaggio, al posto della chat vuota c'è
/// un'intestazione "È un incontro" con le due foto, la proposta della
/// richiesta ("🥤 Bere qualcosa insieme") e un suggerimento per rompere il
/// ghiaccio adatto a quella proposta.
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
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    context.read<ProChat>().open(
      otherPersonId: widget.request.otherPersonId,
      otherSelfieBytes: widget.request.otherSelfieBytes,
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

  Future<void> _send() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final sending = context.read<ProChat>().sendMessage(text);
    _textController.clear();
    final failure = await sending;
    // Troppo lungo (il limite conta in unità UTF-16 come il server, il
    // campo in caratteri visibili: con molte emoji si può sforare): il
    // testo torna nel campo, da accorciare.
    if (failure is MessageTooLongFailure && mounted) {
      if (_textController.text.isEmpty) _textController.text = text;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.chat_message_too_long(failure.maxLength))),
      );
    }
  }

  static Widget? _buildLengthCounter(
    BuildContext context, {
    required int currentLength,
    required bool isFocused,
    required int? maxLength,
  }) {
    if (maxLength == null || currentLength < maxLength - 100) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 4),
      child: Text(
        '$currentLength/$maxLength',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }

  Future<bool> _confirmLeave(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.end_this_match),
        content: Text(l10n.youll_lose_contact_with_this_person_for_good),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.stay),
          ),
          // Azione irreversibile: rosso errore, non il primario.
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l10n.end_it),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _leaveMatch(AppLocalizations l10n) async {
    if (_isLeaving) return;
    final confirmed = await _confirmLeave(l10n);
    if (!confirmed || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _isLeaving = true);
    final result = await context.read<ProEncounters>().endMatch(
      requestId: widget.request.id,
      otherPersonId: widget.request.otherPersonId,
    );
    if (!mounted) return;
    setState(() => _isLeaving = false);

    result.match(
      // Non è partita: il match non è finito, la pagina resta.
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failure is ConnectionFailure
                ? l10n.action_not_sent_offline
                : l10n.action_failed_generic,
          ),
        ),
      ),
      (_) => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final proChat = context.watch<ProChat>();
    final photo = imageProviderForPhoto(widget.request.otherSelfieBytes);
    // La propria foto è un di più per l'intestazione: senza sessione (o
    // senza `ProSession` sopra, come nei test) si mostra solo l'altra.
    final ownPhoto = imageProviderForPhoto(
      context.select<ProSession?, Uint8List?>(
        (proSession) => proSession?.session?.selfieBytes,
      ),
    );

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
              _MatchPhoto(photo: photo),
              const SizedBox(width: 12),
              Text(l10n.chat),
            ],
          ),
          actions: [
            CmpEndButton(
              label: l10n.end_match,
              isBusy: _isLeaving,
              onPressed: () => _leaveMatch(l10n),
            ),
          ],
        ),
        body: proChat.isLoading
            ? const Center(child: CmpLoadingIndicator())
            : Column(
                children: [
                  const CmpConnectionBanner(),
                  if (proChat.failure != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: CmpInlineError(
                        message: l10n.action_failed_generic,
                      ),
                    ),
                  Expanded(
                    child: Container(
                      // Sfondo appena tinto di blu (surfaceContainerLow) per
                      // staccare l'area dei messaggi dall'AppBar/barra di
                      // composizione, come lo sfondo distinto (per noi tinto,
                      // non un motivo grafico preso da un'altra app) dietro
                      // le chat di WhatsApp.
                      color: colorScheme.surfaceContainerLow,
                      child: proChat.messages.isEmpty
                          ? _MatchIntro(
                              ownPhoto: ownPhoto,
                              otherPhoto: photo,
                              proposal: widget.request.proposal,
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.all(16),
                              itemCount: proChat.messages.length,
                              itemBuilder: (context, index) {
                                final message =
                                    proChat.messages[proChat.messages.length -
                                        1 -
                                        index];
                                final isUnsent = proChat.isUnsent(message);
                                return CmpChatMessageBubble(
                                  message: message,
                                  isUnsent: isUnsent,
                                  onRetry: isUnsent
                                      ? () => context.read<ProChat>().resend(
                                          message,
                                        )
                                      : null,
                                );
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
                              constraints: const BoxConstraints(minHeight: 48),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _textController,
                                focusNode: _textFieldFocusNode,
                                minLines: 1,
                                maxLines: 5,
                                // Lo stesso limite del server (vedi
                                // `SendMessageUseCase`); il contatore
                                // compare solo vicino al limite.
                                maxLength: SendMessageUseCase.maxTextLength,
                                buildCounter: _buildLengthCounter,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: l10n.write_a_message,
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

/// Foto dell'altra persona nell'AppBar col cuore nel disco bianco, come
/// nell'icona dell'app: segnala a colpo d'occhio che questo è un match.
class _MatchPhoto extends StatelessWidget {
  const _MatchPhoto({required this.photo});

  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final raen = RaenColors.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        CmpPhoto(image: photo, size: 40),
        Positioned(
          right: -6,
          bottom: -6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: raen.heartDisc,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Icon(Icons.favorite, size: 14, color: raen.onHeartDisc),
            ),
          ),
        ),
      ],
    );
  }
}

/// Intestazione della chat ancora vuota: le due foto affiancate col cuore
/// nel disco bianco in mezzo (come nell'icona), "È un incontro", cosa era
/// stato proposto e un suggerimento per il primo messaggio adatto a quella
/// proposta. Sparisce al primo messaggio.
class _MatchIntro extends StatelessWidget {
  const _MatchIntro({
    required this.ownPhoto,
    required this.otherPhoto,
    required this.proposal,
  });

  final ImageProvider? ownPhoto;
  final ImageProvider? otherPhoto;
  final EncounterProposal proposal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: _PhotoPair(ownPhoto: ownPhoto, otherPhoto: otherPhoto),
              ),
              const SizedBox(height: 28),
              Semantics(
                header: true,
                child: Text(
                  l10n.its_a_match_title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Text(
                      EncounterProposalLabels.emoji(proposal),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      EncounterProposalLabels.matchSubtitle(l10n, proposal),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                EncounterProposalLabels.icebreaker(l10n, proposal),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La tua foto e la sua, appena inclinate e sovrapposte, con il cuore in
/// basso al centro. Senza la tua foto resta solo la sua, col cuore.
class _PhotoPair extends StatelessWidget {
  const _PhotoPair({required this.ownPhoto, required this.otherPhoto});

  final ImageProvider? ownPhoto;
  final ImageProvider? otherPhoto;

  static const double _size = 104;
  static const double _overlap = 20;
  static const double _frame = 3;
  static const double _tilt = 0.07;

  @override
  Widget build(BuildContext context) {
    final hasOwn = ownPhoto != null;
    const framed = _size + _frame * 2;
    const pairWidth = framed * 2 - _overlap;

    return SizedBox(
      width: hasOwn ? pairWidth : framed,
      height: framed + 14,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (hasOwn)
            Positioned(
              left: 0,
              top: 0,
              child: _framed(context, ownPhoto, -_tilt),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: _framed(context, otherPhoto, hasOwn ? _tilt : 0),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(child: _heart(context)),
          ),
        ],
      ),
    );
  }

  /// Cornice nel colore del fondo della chat: separa le due foto dove si
  /// sovrappongono.
  Widget _framed(BuildContext context, ImageProvider? photo, double angle) {
    return Transform.rotate(
      angle: angle,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(
            CmpPhoto.radiusFor(_size) + _frame,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_frame),
          child: CmpPhoto(image: photo, size: _size),
        ),
      ),
    );
  }

  Widget _heart(BuildContext context) {
    final raen = RaenColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: raen.heartDisc,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.surfaceContainerLow, width: 3),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(Icons.favorite, size: 22, color: raen.onHeartDisc),
      ),
    );
  }
}
