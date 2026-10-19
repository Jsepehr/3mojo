import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '/core/errors/failures.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_rejection.dart';
import '../encounter_notice.dart';
import '../providers/pro_encounters.dart';

/// Racconta con una snackbar ciò che succede alle richieste d'incontro
/// ([EncounterNotice] da `ProEncounters`): richiesta confermata dal
/// server, non partita (offline, già richiesta), rifiutata dal server e
/// perché, match finito dall'altra parte. Sta in cima all'app
/// (`app.dart`), sopra ogni pagina. I testi vengono dagli ARB in base al
/// **tipo** di evento/`Failure`, mai dal `message` tecnico.
class CmpEncounterNoticeListener extends StatefulWidget {
  const CmpEncounterNoticeListener({super.key, required this.child});

  final Widget child;

  @override
  State<CmpEncounterNoticeListener> createState() =>
      _CmpEncounterNoticeListenerState();
}

class _CmpEncounterNoticeListenerState
    extends State<CmpEncounterNoticeListener> {
  StreamSubscription<EncounterNotice>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<ProEncounters>().notices.listen(_show);
  }

  void _show(EncounterNotice notice) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(encounterNoticeText(l10n, notice))),
      );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Il testo (tradotto) di un [EncounterNotice].
String encounterNoticeText(AppLocalizations l10n, EncounterNotice notice) =>
    switch (notice) {
      RequestSentNotice() => l10n.request_sent,
      ActionNotSentNotice(:final action, :final failure) => switch ((
        action,
        failure,
      )) {
        (EncounterAction.sendRequest, ConnectionFailure()) =>
          l10n.request_not_sent_offline,
        (EncounterAction.sendRequest, AlreadyRequestedFailure()) =>
          l10n.request_rejected_already_requested,
        (EncounterAction.sendRequest, RequestNotConfirmedFailure()) =>
          l10n.request_not_confirmed,
        (EncounterAction.sendRequest, _) => l10n.request_not_sent_generic,
        (_, ConnectionFailure()) => l10n.action_not_sent_offline,
        _ => l10n.action_failed_generic,
      },
      ActionRejectedNotice(:final rejection) => _rejectionText(l10n, rejection),
      MatchEndedByPartnerNotice() => l10n.match_ended_partner_left,
    };

String _rejectionText(
  AppLocalizations l10n,
  EncounterRejection rejection,
) => switch ((rejection.action, rejection.reason)) {
  (
    EncounterAction.sendRequest,
    EncounterRejectionReason.notNearby || EncounterRejectionReason.notOnline,
  ) =>
    l10n.request_rejected_not_nearby,
  (EncounterAction.sendRequest, EncounterRejectionReason.alreadyRequested) =>
    l10n.request_rejected_already_requested,
  (EncounterAction.sendRequest, EncounterRejectionReason.inMatch) =>
    l10n.request_rejected_in_match,
  (EncounterAction.sendRequest, EncounterRejectionReason.tooManyPending) =>
    l10n.request_rejected_too_many,
  (EncounterAction.sendRequest, _) => l10n.request_not_sent_generic,
  (EncounterAction.respondToRequest, EncounterRejectionReason.inMatch) =>
    l10n.response_rejected_in_match,
  (EncounterAction.respondToRequest, _) => l10n.action_failed_generic,
};
