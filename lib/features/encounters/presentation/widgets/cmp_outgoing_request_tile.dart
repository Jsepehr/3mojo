import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';

class CmpOutgoingRequestTile extends StatelessWidget {
  const CmpOutgoingRequestTile({super.key, required this.request});

  final EncounterRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: request.otherSelfiePath.isEmpty
            ? null
            : FileImage(File(request.otherSelfiePath)),
        child: request.otherSelfiePath.isEmpty
            ? const Icon(Icons.person)
            : null,
      ),
      title: Text(_statusLabel(l10n, request.status)),
    );
  }

  String _statusLabel(AppLocalizations l10n, EncounterRequestStatus status) {
    switch (status) {
      case EncounterRequestStatus.pending:
        return l10n.encountersStatusPending;
      case EncounterRequestStatus.accepted:
        return l10n.encountersStatusAccepted;
      case EncounterRequestStatus.declined:
        return l10n.encountersStatusDeclined;
      case EncounterRequestStatus.cancelled:
        return l10n.encountersStatusCancelled;
      case EncounterRequestStatus.ended:
        return l10n.encountersStatusEnded;
    }
  }
}
