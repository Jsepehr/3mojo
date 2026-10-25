import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/widgets/cmp_busy_filled_button.dart';
import '/core/widgets/cmp_inline_error.dart';
import '/features/demo/presentation/providers/pro_demo.dart';
import '/features/demo/presentation/widgets/cmp_try_demo_link.dart';
import '/features/profile/domain/entities/profile.dart';
import '/features/profile/presentation/providers/pro_profile.dart';
import '/features/profile/presentation/profile_labels.dart';
import '/features/profile/presentation/widgets/cmp_intent_chip.dart';
import '/features/safety/presentation/pages/ui_privacy_policy.dart';
import '/features/safety/presentation/pages/ui_terms_of_use.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/l10n/generated/app_localizations.dart';

/// Il profilo: compilato una volta al primo avvio ([isOnboarding], senza
/// tasto indietro — `UiHome` la mostra al posto della home finché manca) e
/// poi modificabile dal menu. Resta cifrato sul telefono; il server lo
/// riceve solo a ogni Start.
///
/// Al primo avvio (e finché il profilo salvato non li ha accettati) chiede
/// anche di accettare i **termini d'uso** attuali: la casella si salva col
/// profilo cifrato (`Profile.acceptedTermsVersion`), la regola sta in
/// `SaveProfileUseCase`. Accanto, i link ai termini e all'informativa
/// privacy.
///
/// Il consenso al dato sensibile è **versionato**
/// (`Profile.acceptedSensitiveConsentVersion`): la casella risulta spuntata
/// solo se il consenso salvato è per il testo attuale, e spuntarla salva la
/// versione attuale.
///
/// Da online, cambiare genere, chi cerchi o "mostra il mio genere" chiude
/// prima la sessione (`UpdateProfileUseCase`): la pagina lo chiede con una
/// conferma prima di salvare. Lingue e intento predefinito valgono dal
/// prossimo Start.
///
/// "Tutti" è la prima scelta di "chi vuoi incontrare" apposta: insieme a
/// "preferisco non dirlo" è il percorso che non rivela nulla e non richiede
/// il consenso al dato sensibile.
class UiProfile extends StatefulWidget {
  const UiProfile({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<UiProfile> createState() => _UiProfileState();
}

class _UiProfileState extends State<UiProfile> {
  Gender? _gender;
  Set<Gender> _lookingFor = {};
  bool _showGender = false;
  MeetIntent? _defaultIntent;
  List<String> _languages = [];
  bool _isAdultConfirmed = false;
  bool _sensitiveDataConsent = false;
  bool _termsAccepted = false;
  bool _isSaving = false;

  /// Finché l'errore di una visita precedente non è stato azzerato (dopo il
  /// primo frame: non si può notificare durante il build), non lo si mostra.
  bool _staleErrorCleared = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProProfile>().clearError();
      setState(() => _staleErrorCleared = true);
    });
    final existing = context.read<ProProfile>().profile;
    if (existing != null) {
      _gender = existing.gender;
      _lookingFor = {...existing.lookingFor};
      _showGender = existing.showGender;
      _defaultIntent = existing.defaultIntent;
      _languages = [...existing.languages];
      _isAdultConfirmed = existing.isAdultConfirmed;
      _sensitiveDataConsent = existing.hasCurrentSensitiveConsent;
      _termsAccepted = existing.hasAcceptedCurrentTerms;
    }
  }

  Profile? get _draft {
    final gender = _gender;
    if (gender == null) return null;
    return Profile(
      gender: gender,
      lookingFor: _lookingFor,
      isAdultConfirmed: _isAdultConfirmed,
      acceptedSensitiveConsentVersion: _sensitiveDataConsent
          ? Profile.currentSensitiveConsentVersion
          : 0,
      defaultIntent: _defaultIntent,
      languages: _languages,
      showGender: _showGender,
      acceptedTermsVersion: _termsAccepted ? Profile.currentTermsVersion : 0,
    );
  }

  bool get _canSave {
    final draft = _draft;
    if (draft == null) return false;
    return draft.lookingFor.isNotEmpty &&
        draft.isAdultConfirmed &&
        draft.hasAcceptedCurrentTerms &&
        !draft.lacksRequiredSensitiveConsent;
  }

  /// Da online, se la modifica tocca il dato sensibile, prima la conferma:
  /// salvare chiude la sessione (la regola sta in `UpdateProfileUseCase`).
  Future<void> _save(AppLocalizations l10n) async {
    final draft = _draft;
    if (draft == null) return;
    final proProfile = context.read<ProProfile>();
    final isOnline = context.read<ProSession>().isOnline;

    // Il controllo è immediato (sessione in memoria): niente puntini nel
    // bottone mentre si legge la conferma.
    final endsSession = isOnline && await proProfile.saveEndsSession(draft);
    if (!mounted) return;
    if (endsSession && !await _confirmEndingSession(l10n)) return;
    if (!mounted) return;

    setState(() => _isSaving = true);
    final saved = await proProfile.save(draft);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (saved && !widget.isOnboarding) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            endsSession ? l10n.profile_saved_session_ended : l10n.profile_saved,
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmEndingSession(AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.profile_save_ends_session_title),
        content: Text(l10n.profile_save_ends_session_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.profile_save_and_end),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Da online la conferma lo dice: prima si va offline (End), poi il
  /// profilo sparisce — la regola sta in `WithdrawProfileUseCase`.
  Future<void> _delete(AppLocalizations l10n) async {
    final isOnline = context.read<ProSession>().isOnline;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete_your_profile),
        content: Text(
          isOnline
              ? '${l10n.this_removes_it_from_this_phone_and_withdraws_your_consent}'
                    '\n\n${l10n.deleting_the_profile_ends_your_session}'
              : l10n.this_removes_it_from_this_phone_and_withdraws_your_consent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await context.read<ProProfile>().delete();
    if (deleted && mounted) Navigator.of(context).pop();
  }

  void _toggleLookingFor(Gender gender, bool selected) {
    setState(() {
      selected ? _lookingFor.add(gender) : _lookingFor.remove(gender);
    });
  }

  void _toggleEveryone(bool selected) {
    setState(() {
      _lookingFor = selected ? {...Profile.searchableGenders} : {};
    });
  }

  void _toggleLanguage(String code, bool selected) {
    setState(() {
      selected ? _languages.add(code) : _languages.remove(code);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final proProfile = context.watch<ProProfile>();
    final failure = _staleErrorCleared ? proProfile.failure : null;
    final isOnline = context.watch<ProSession>().isOnline;
    final draft = _draft;
    final needsConsent = draft?.needsSensitiveDataConsent ?? true;
    final looksForEveryone = _lookingFor.containsAll(Profile.searchableGenders);

    Widget section(String title, {String? hint}) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.my_profile),
        automaticallyImplyLeading: !widget.isOnboarding,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              l10n.answer_once_it_stays_encrypted_on_this_phone,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (isOnline && !widget.isOnboarding) ...[
              const SizedBox(height: 8),
              Text(
                l10n.profile_online_changes_hint,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            // Al primo avvio la demo dichiarata si può provare anche prima
            // di compilare il profilo (la demo ha un profilo neutro suo).
            if (widget.isOnboarding && context.watch<ProDemo?>() != null)
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: CmpTryDemoLink(),
              ),
            section(l10n.you_are),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final gender in Gender.values)
                  ChoiceChip(
                    label: Text(ProfileLabels.gender(l10n, gender)),
                    selected: _gender == gender,
                    onSelected: (_) => setState(() {
                      _gender = gender;
                      if (gender == Gender.unspecified) _showGender = false;
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.show_my_gender_to_others),
              value: _showGender,
              onChanged: _gender == null || _gender == Gender.unspecified
                  ? null
                  : (value) => setState(() => _showGender = value),
            ),
            section(
              l10n.who_do_you_want_to_meet,
              hint: l10n.never_shown_to_anyone,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(l10n.everyone),
                  selected: looksForEveryone,
                  onSelected: _toggleEveryone,
                ),
                for (final gender in Profile.searchableGenders)
                  FilterChip(
                    label: Text(ProfileLabels.lookingFor(l10n, gender)),
                    selected: _lookingFor.contains(gender),
                    onSelected: (selected) =>
                        _toggleLookingFor(gender, selected),
                  ),
              ],
            ),
            section(
              l10n.what_are_you_usually_looking_for,
              hint: l10n.optional_shown_to_people_nearby,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final intent in MeetIntent.values)
                  CmpIntentChip(
                    intent: intent,
                    selected: _defaultIntent == intent,
                    // Un secondo tap deseleziona: l'intento è facoltativo.
                    onSelected: (selected) => setState(
                      () => _defaultIntent = selected ? intent : null,
                    ),
                  ),
              ],
            ),
            section(l10n.languages_you_speak_up_to_2),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in Profile.supportedLanguages)
                  FilterChip(
                    label: Text(code.toUpperCase()),
                    selected: _languages.contains(code),
                    onSelected:
                        _languages.contains(code) ||
                            _languages.length < Profile.maxLanguages
                        ? (selected) => _toggleLanguage(code, selected)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.i_confirm_i_am_at_least_18_years_old),
              value: _isAdultConfirmed,
              onChanged: (value) =>
                  setState(() => _isAdultConfirmed = value ?? false),
            ),
            if (needsConsent)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  l10n.i_agree_that_raen_uses_my_gender_and_who_i_want_to_meet,
                  style: theme.textTheme.bodyMedium,
                ),
                value: _sensitiveDataConsent,
                onChanged: (value) =>
                    setState(() => _sensitiveDataConsent = value ?? false),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                l10n.terms_accept_checkbox,
                style: theme.textTheme.bodyMedium,
              ),
              value: _termsAccepted,
              onChanged: (value) =>
                  setState(() => _termsAccepted = value ?? false),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.read_the_terms),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const UiTermsOfUse())),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text(l10n.read_the_privacy_policy),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UiPrivacyPolicy()),
                ),
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: 8),
              CmpInlineError(message: ProfileLabels.failure(l10n, failure)),
            ],
            const SizedBox(height: 24),
            // Durante il salvataggio: puntini nel bottone, niente doppio tap.
            CmpBusyFilledButton(
              label: l10n.save,
              isBusy: _isSaving,
              onPressed: _canSave ? () => _save(l10n) : null,
            ),
            if (!widget.isOnboarding && proProfile.hasProfile) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _delete(l10n),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.delete_profile),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
