import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/core/errors/failures.dart';
import '/core/theme/raen_colors.dart';
import '/core/widgets/cmp_busy_filled_button.dart';
import '/core/widgets/cmp_inline_error.dart';
import '/core/widgets/cmp_loading_indicator.dart';
import '/core/widgets/cmp_photo.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/profile/presentation/providers/pro_profile.dart';
import '/features/profile/presentation/widgets/cmp_intent_chip.dart';
import '/features/profile/presentation/widgets/cmp_sensitive_consent_renewal_dialog.dart';
import '/features/safety/presentation/widgets/cmp_terms_acceptance_dialog.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/features/session/presentation/session_failure_texts.dart';
import '/l10n/generated/app_localizations.dart';

/// Wizard aperto da "Start": prima il selfie (scatta e confermi — un
/// controllo sul dispositivo verifica al volo che ci sia un volto,
/// altrimenti blocca il passo), poi cosa si cerca adesso (facoltativo,
/// precompilato dal profilo). Genere e "chi cerchi" non si chiedono più qui:
/// vengono dal profilo salvato sul telefono. Alla fine avvia la sessione e
/// torna alla home.
///
/// Il selfie vive solo qui, in memoria ([_selfieBytes]): scatto e
/// ribaltamento passano da `ProSession` (use case), nessun file resta su
/// disco e nessuna manipolazione d'immagine sta in questa pagina.
class UiStartSession extends StatefulWidget {
  const UiStartSession({super.key});

  @override
  State<UiStartSession> createState() => _UiStartSessionState();
}

class _UiStartSessionState extends State<UiStartSession> {
  int _step = 0;
  Uint8List? _selfieBytes;
  // Cosa si cerca in questa sessione: parte dall'intento predefinito del
  // profilo, si cambia qui con un tap.
  late MeetIntent? _intent = context.read<ProProfile>().profile?.defaultIntent;
  bool _isCheckingFace = false;
  bool _isFlipping = false;
  bool _isStarting = false;

  /// Finché l'errore di un tentativo precedente non è stato azzerato (dopo
  /// il primo frame: non si può notificare durante il build), non lo si
  /// mostra nemmeno per un istante.
  bool _staleErrorCleared = false;

  bool get _isBusy => _isFlipping || _isCheckingFace;

  static const double _selfieSize = 220;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProSession>().clearError();
      setState(() => _staleErrorCleared = true);
    });
  }

  /// Ogni nuovo scatto (anche "Rifai") azzera l'errore di quello prima.
  Future<void> _takeSelfie() async {
    final bytes = await context.read<ProSession>().takeSelfie();
    if (!mounted || bytes == null) return;

    setState(() => _selfieBytes = bytes);
  }

  /// La fotocamera frontale, su molti dispositivi Android, salva lo scatto
  /// come immagine speculare: l'utente decide se serve la correzione col
  /// bottone sopra il selfie. Tutto in memoria (`FlipSelfieUseCase`).
  Future<void> _flipSelfie() async {
    final bytes = _selfieBytes;
    if (bytes == null) return;

    setState(() => _isFlipping = true);
    final flipped = await context.read<ProSession>().flipSelfie(bytes);
    if (!mounted) return;

    setState(() {
      if (flipped != null) _selfieBytes = flipped;
      _isFlipping = false;
    });
  }

  Future<void> _confirmSelfie() async {
    final bytes = _selfieBytes;
    if (bytes == null) return;

    setState(() => _isCheckingFace = true);
    final hasFace = await context.read<ProSession>().checkSelfieHasFace(bytes);
    if (!mounted) return;

    setState(() {
      _isCheckingFace = false;
      if (hasFace) _step = 1;
    });
  }

  /// Si chiude solo a sessione già avviata: chiudendo subito, durante la
  /// transizione si vedeva per un attimo la home ancora offline (e un
  /// eventuale errore finiva su una pagina già chiusa). Così, quando la
  /// pagina scorre via, sotto c'è già la home online.
  Future<void> _submit() async {
    final selfieBytes = _selfieBytes;
    if (selfieBytes == null) return;

    final proSession = context.read<ProSession>();
    final proProfile = context.read<ProProfile>();
    final params = StartSessionParams(
      selfieBytes: selfieBytes,
      intent: _intent,
    );
    setState(() => _isStarting = true);
    await proSession.start(params);
    if (!mounted) return;

    // Profilo salvato prima dei termini d'uso attuali, o con il consenso al
    // dato sensibile dato per un testo precedente: si chiedono qui, una
    // volta ciascuno, e confermati si riprova subito. Rifiutati, resta
    // l'errore che lo dice. Ognuno al più una volta: un secondo rifiuto
    // dello stesso tipo non riapre lo stesso dialog.
    var askedTerms = false;
    var askedConsent = false;
    while (mounted) {
      final failure = proSession.failure;
      final Future<bool> Function() ask;
      final Future<bool> Function() save;
      if (failure is TermsNotAcceptedFailure && !askedTerms) {
        askedTerms = true;
        ask = () => showTermsAcceptanceDialog(context);
        save = proProfile.acceptTerms;
      } else if (failure is SensitiveDataConsentRequiredFailure &&
          !askedConsent) {
        askedConsent = true;
        ask = () => showSensitiveConsentRenewalDialog(context);
        save = proProfile.renewSensitiveConsent;
      } else {
        break;
      }
      // Niente puntini nel bottone mentre si legge il dialog.
      setState(() => _isStarting = false);
      final confirmed = await ask();
      if (!mounted || !confirmed) break;
      setState(() => _isStarting = true);
      if (!await save() || !mounted) break;
      await proSession.start(params);
    }
    if (!mounted) return;

    if (proSession.isOnline) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
    } else {
      setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentFailure = context.watch<ProSession>().failure;
    final failure = _staleErrorCleared ? currentFailure : null;
    final errorMessage = failure == null
        ? null
        : SessionFailureTexts.of(l10n, failure);

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.go_online_title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        // Dal selfie all'intento: il passo nuovo entra da destra sfumando.
        // Con le animazioni ridotte di sistema il cambio è immediato.
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // Una closure nuova a ogni build (non il tear-off, che sarebbe
          // uguale): così AnimatedSwitcher ricostruisce anche la
          // transizione del passo che esce, con la direzione giusta.
          transitionBuilder: (child, animation) =>
              _stepTransition(child, animation),
          layoutBuilder: (current, previous) =>
              Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: KeyedSubtree(
            key: ValueKey(_step),
            child: _step == 0
                ? _buildSelfieStep(l10n, errorMessage)
                : _buildIntentStep(l10n, errorMessage),
          ),
        ),
      ),
    );
  }

  /// Il passo che entra arriva da destra, quello che esce scivola a
  /// sinistra (la sua animazione gira all'indietro, da 1 a 0): sempre in
  /// avanti, sfumando.
  Widget _stepTransition(Widget child, Animation<double> animation) {
    final isIncoming = child.key == ValueKey(_step);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: Offset(isIncoming ? 0.08 : -0.08, 0),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  Widget _buildSelfieStep(AppLocalizations l10n, String? errorMessage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: _isBusy ? null : _takeSelfie,
                child: CmpPhoto(
                  image: _selfieBytes == null
                      ? null
                      : MemoryImage(_selfieBytes!),
                  size: _selfieSize,
                  placeholderIcon: Icons.camera_alt,
                ),
              ),
              if (_isFlipping)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RaenColors.of(context).photoScrim,
                      borderRadius: BorderRadius.circular(
                        CmpPhoto.radiusFor(_selfieSize),
                      ),
                    ),
                    child: Center(
                      child: CmpLoadingIndicator(
                        color: RaenColors.of(context).onPhoto,
                      ),
                    ),
                  ),
                ),
              if (_selfieBytes != null)
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton.filled(
                    onPressed: _isFlipping ? null : _flipSelfie,
                    tooltip: l10n.flip_photo,
                    icon: const Icon(Icons.flip),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isBusy ? null : _takeSelfie,
            child: Text(
              _selfieBytes == null ? l10n.take_a_selfie : l10n.retake,
            ),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          CmpInlineError(message: errorMessage),
        ],
        const Spacer(),
        CmpBusyFilledButton(
          label: l10n.i_like_it_continue,
          isBusy: _isCheckingFace,
          onPressed: _selfieBytes == null || _isFlipping
              ? null
              : _confirmSelfie,
        ),
      ],
    );
  }

  Widget _buildIntentStep(AppLocalizations l10n, String? errorMessage) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.what_are_you_looking_for_right_now,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.optional_shown_to_people_nearby,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final intent in MeetIntent.values)
              CmpIntentChip(
                intent: intent,
                selected: _intent == intent,
                // Un secondo tap deseleziona: l'intento è facoltativo.
                onSelected: (selected) =>
                    setState(() => _intent = selected ? intent : null),
              ),
          ],
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          CmpInlineError(message: errorMessage),
        ],
        const Spacer(),
        CmpBusyFilledButton(
          label: l10n.go_online_button,
          isBusy: _isStarting,
          onPressed: _submit,
        ),
      ],
    );
  }
}
