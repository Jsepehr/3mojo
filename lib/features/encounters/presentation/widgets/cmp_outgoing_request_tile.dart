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
