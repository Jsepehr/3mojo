import 'package:flutter/material.dart';

import '/core/utils/photo_data_uri.dart';
import '/core/widgets/cmp_photo.dart';
import '/l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';

/// Riga di una richiesta mandata da te, con il suo stato testuale.
class CmpOutgoingRequestTile extends StatelessWidget {
  const CmpOutgoingRequestTile({super.key, required this.request});

  final EncounterRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final photo = imageProviderForPhoto(request.otherSelfiePath);

    return ListTile(
      leading: CmpPhoto(image: photo, size: 56),
      title: Text(_statusLabel(l10n, request.status)),
    );
  }

  String _statusLabel(AppLocalizations l10n, EncounterRequestStatus status) {
    switch (status) {
      case EncounterRequestStatus.pending:
        return l10n.waiting_for_a_reply;
      case EncounterRequestStatus.accepted:
        return l10n.accepted;
      case EncounterRequestStatus.declined:
        return l10n.declined;
      case EncounterRequestStatus.cancelled:
        return l10n.cancelled_you_matched_with_someone_else;
      case EncounterRequestStatus.ended:
        return l10n.ended;
    }
  }
}
