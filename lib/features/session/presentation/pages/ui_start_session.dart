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
import '/features/profile/presentation/providers/pro_profile.dart';
import '/features/profile/presentation/widgets/cmp_sensitive_consent_renewal_dialog.dart';
import '/features/safety/presentation/widgets/cmp_terms_acceptance_dialog.dart';
import '/features/session/domain/entities/meet_place.dart';
import '/features/session/domain/usecases/start_session_usecase.dart';
import '/features/session/presentation/meet_place_labels.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/features/session/presentation/session_failure_texts.dart';
import '/l10n/generated/app_localizations.dart';

/// Pagina aperta da "Start": il selfie (scatta; al "Vai online" un controllo
/// sul dispositivo verifica che ci sia un volto, altrimenti si ferma lì) e,
/// subito sotto l'anteprima, un menu a tendina "Dove ti trovi?" (facoltativo,
/// di partenza "Altro / preferisco non dirlo"): il luogo vale solo per
/// questa sessione e non si cambia da online (per cambiarlo, End e Start).
/// Genere e "chi cerchi" non si chiedono qui: vengono dal profilo salvato sul
/// telefono. Alla fine avvia la sessione e torna alla home.
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
  Uint8List? _selfieBytes;
  // Dove ci si trova in questa sessione: mai ricordato tra una sessione e
  // l'altra (non sta nel profilo), parte sempre da "Altro".
  MeetPlace _place = MeetPlace.fallback;
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

  /// Si chiude solo a sessione già avviata: chiudendo subito, durante la
  /// transizione si vedeva per un attimo la home ancora offline (e un
  /// eventuale errore finiva su una pagina già chiusa). Così, quando la
  /// pagina scorre via, sotto c'è già la home online.
  Future<void> _submit() async {
    final selfieBytes = _selfieBytes;
    if (selfieBytes == null) return;

    final proSession = context.read<ProSession>();
    final proProfile = context.read<ProProfile>();
    final params = StartSessionParams(selfieBytes: selfieBytes, place: _place);

    // Feedback immediato sul volto (tutto sul dispositivo), prima di
    // avviare: senza volto resta qui, con l'errore a schermo.
    setState(() => _isCheckingFace = true);
    final hasFace = await proSession.checkSelfieHasFace(selfieBytes);
    if (!mounted) return;
    setState(() => _isCheckingFace = false);
    if (!hasFace) return;

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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.go_online_title)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _scrollable(_buildContent(l10n, errorMessage)),
      ),
    );
  }

  /// La pagina scorre se non ci sta (testo grande, orizzontale); altrimenti
  /// occupa tutta l'altezza, così il bottone resta in fondo (`Spacer`).
  Widget _scrollable(Widget content) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(child: content),
      ),
    ),
  );

  Widget _buildContent(AppLocalizations l10n, String? errorMessage) {
    final theme = Theme.of(context);
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
                PositionedDirectional(
                  top: -8,
                  end: -8,
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
        const SizedBox(height: 16),
        // Il luogo, sotto l'anteprima. Il tap target è alto almeno 48 dp
        // (il campo di Material); le emoji sono decorative, il testo dice
        // già tutto allo screen reader; `isExpanded` + ellipsis: niente
        // overflow a 360 dp né con testo grande, e in RTL si specchia da sé.
        DropdownButtonFormField<MeetPlace>(
          key: const ValueKey('place-dropdown'),
          initialValue: _place,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.where_are_you,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final place in MeetPlace.values)
              DropdownMenuItem(
                value: place,
                child: Row(
                  children: [
                    ExcludeSemantics(child: Text(MeetPlaceLabels.emoji(place))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        MeetPlaceLabels.label(l10n, place),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: _isStarting
              ? null
              : (place) => setState(() => _place = place ?? MeetPlace.fallback),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.where_are_you_hint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          CmpInlineError(message: errorMessage),
        ],
        const Spacer(),
        const SizedBox(height: 16),
        CmpBusyFilledButton(
          label: l10n.go_online_button,
          isBusy: _isCheckingFace || _isStarting,
          onPressed: _selfieBytes == null || _isFlipping ? null : _submit,
        ),
      ],
    );
  }
}
