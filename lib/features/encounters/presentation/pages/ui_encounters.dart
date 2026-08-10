import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/entities/encounter_request.dart';
import '../providers/pro_encounters.dart';
import '../widgets/cmp_incoming_request_tile.dart';
import '../widgets/cmp_outgoing_request_tile.dart';

class UiEncounters extends StatelessWidget {
  const UiEncounters({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proEncounters = context.watch<ProEncounters>();

    final pendingIncoming = proEncounters.incomingRequests
        .where((r) => r.status == EncounterRequestStatus.pending)
        .toList();
    final outgoing = proEncounters.outgoingRequests;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.encountersPageTitle)),
      body: ListView(
        children: [
          if (pendingIncoming.isNotEmpty) ...[
            _SectionHeader(title: l10n.encountersIncomingSectionTitle),
            for (final request in pendingIncoming)
              CmpIncomingRequestTile(
                request: request,
                onAccept: () => context.read<ProEncounters>().respondToRequest(
                  request.id,
                  true,
                ),
                onDecline: () => context.read<ProEncounters>().respondToRequest(
                  request.id,
                  false,
                ),
              ),
          ],
          _SectionHeader(title: l10n.encountersOutgoingSectionTitle),
          if (outgoing.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.encountersEmptyMessage,
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final request in outgoing)
              CmpOutgoingRequestTile(request: request),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
