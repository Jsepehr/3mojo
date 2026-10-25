import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '/core/demo/demo_mode.dart';
import '/core/theme/app_theme.dart';
import '/core/widgets/cmp_end_button.dart';
import '/core/widgets/cmp_loading_indicator.dart';
import '/core/widgets/cmp_photo.dart';
import '/core/widgets/cmp_radar_background.dart';
import '/features/demo/presentation/widgets/cmp_demo_nearby_note.dart';
import '/features/demo/presentation/widgets/cmp_try_demo_link.dart';
import '/features/encounters/domain/entities/encounter_request.dart';
import '/features/encounters/presentation/pages/ui_encounters.dart';
import '/features/encounters/presentation/providers/pro_encounters.dart';
import '/features/encounters/presentation/widgets/cmp_proposal_sheet.dart';
import '/features/nearby/domain/entities/background_location_notice.dart';
import '/features/nearby/domain/entities/nearby_person.dart';
import '/features/nearby/presentation/pages/ui_location_disclosure.dart';
import '/features/nearby/presentation/providers/pro_nearby.dart';
import '/features/nearby/presentation/widgets/cmp_nearby_person_tile.dart';
import '/features/paywall/presentation/widgets/cmp_paywalled_nearby_list.dart';
import '/features/profile/presentation/pages/ui_profile.dart';
import '/features/profile/presentation/providers/pro_profile.dart';
import '/features/safety/presentation/widgets/cmp_person_safety_menu_button.dart';
import '/features/session/presentation/providers/pro_session.dart';
import '/features/session/presentation/widgets/cmp_connection_banner.dart';
import '/features/settings/presentation/widgets/cmp_app_drawer.dart';
import '/l10n/generated/app_localizations.dart';
import 'ui_start_session.dart';

/// Pagina iniziale dell'app: un'unica pagina che cambia aspetto in base a
/// `ProSession.isOnline`, non due pagine separate. Al primo avvio, finché
/// il profilo non è compilato (e non si è online), mostra `UiProfile` al
/// suo posto — niente gate separato davanti all'app.
///
/// È anche il punto in cui si compongono le feature della home (lista
/// vicinanze col paywall, richieste d'incontro, sessione): le passa tra
/// loro come callback, così nessuna deve importare le altre.
///
/// Dentro la **demo dichiarata** (`DemoMode`, `DemoScope`) è la stessa
/// pagina sui provider della demo: online subito (la sessione della demo),
/// senza drawer (profilo e impostazioni sono del mondo reale) e con una
/// riga che spiega l'attesa di un minuto che nella demo non c'è. Da
/// offline, nella demo, solo l'indicatore: la sessione della demo sta
/// partendo o finendo, e la home offline (con Start) non è della demo.
class UiHome extends StatelessWidget {
  const UiHome({super.key});

  @override
  Widget build(BuildContext context) {
    final proSession = context.watch<ProSession>();
    final proProfile = context.watch<ProProfile>();
    final isDemo = DemoMode.isActive(context);

    if (proSession.isLoading ||
        proProfile.isLoading ||
        (isDemo && !proSession.isOnline)) {
      // Nel tema hero, come la home offline che quasi sempre segue: niente
      // lampo bianco prima del blu.
      return Theme(
        data: AppTheme.hero(Theme.of(context)),
        child: const Scaffold(body: Center(child: CmpLoadingIndicator())),
      );
    }

    if (!proSession.isOnline && !proProfile.hasProfile) {
      return const UiProfile(isOnboarding: true);
    }

    return proSession.isOnline ? const _OnlineHome() : const _OfflineHome();
  }
}

/// Apre il wizard di Start. Prima, se il permesso di posizione non è ancora
/// concesso, l'avviso in evidenza e la richiesta di sistema
/// (`showLocationDisclosureIfNeeded`): con "Non ora" o senza permesso si
/// resta offline e il wizard non si apre. Poi passa a `ProNearby` i testi
/// tradotti della notifica Android che accompagnerà la posizione in
/// background durante la sessione (il datasource GPS non ha un
/// `BuildContext`).
Future<void> _openStartSession(BuildContext context) async {
  final navigator = Navigator.of(context);
  if (!await showLocationDisclosureIfNeeded(context)) return;
  if (!navigator.mounted) return;
  final navigatorContext = navigator.context;
  if (!navigatorContext.mounted) return;
  final l10n = AppLocalizations.of(navigatorContext)!;
  navigatorContext.read<ProNearby>().setBackgroundLocationNotice(
    BackgroundLocationNotice(
      title: l10n.background_location_notification_title,
      body: l10n.background_location_notification_body,
      channelName: l10n.background_location_notification_channel,
    ),
  );
  navigator.push(MaterialPageRoute(builder: (_) => const UiStartSession()));
}

/// Stato offline: claim + bottone Start, sfondo radar decorativo. Usa il
/// tema "hero" (`AppTheme.hero`): blu pieno del brand, testi e radar bianchi,
/// Start come pillola bianca — l'unica schermata immersiva dell'app.
class _OfflineHome extends StatelessWidget {
  const _OfflineHome();

  /// Il radar è centrato un po' più in alto del centro dello schermo (circa
  /// 1 cm: ~63 px logici, a 160 px per pollice), per lasciare più aria al
  /// testo e al bottone Start in basso.
  static const _radarLift = 63.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appTheme = Theme.of(context);

    return Theme(
      data: AppTheme.hero(appTheme),
      // Builder: i widget sotto devono leggere il tema hero, non quello
      // del `context` esterno.
      child: Builder(
        builder: (context) => Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(),
          // Il drawer resta col tema normale dell'app, non quello blu.
          drawer: Theme(data: appTheme, child: const CmpAppDrawer()),
          body: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: -_radarLift,
                bottom: _radarLift,
                child: CmpRadarBackground(),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.meet_people_near_you,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.discover_people_within_100_meters_in_real_time,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 32),
                      FilledButton(
                        onPressed: () => _openStartSession(context),
                        child: Text(l10n.start),
                      ),
                      const SizedBox(height: 8),
                      // Sempre visibile: la demo dichiarata (persone
                      // dimostrative, tutta sul telefono).
                      const CmpTryDemoLink(),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stato online: un'unica pagina — AppBar con bottone End (rosso), body con
/// la lista delle persone vicine, e bottom app bar con la tua foto profilo
/// (piccola, solo a titolo di conferma "sei online con questa foto") e
/// l'icona "Richieste" con badge sulle richieste in attesa.
class _OnlineHome extends StatelessWidget {
  const _OnlineHome();

  /// End (dall'AppBar o dall'avviso d'errore): una vibrazione decisa
  /// conferma il gesto, il resto lo fa `ProSession`.
  void _endSession(BuildContext context) {
    HapticFeedback.mediumImpact();
    context.read<ProSession>().end();
  }

  /// Il server non ha accettato il selfie: si va offline e si riapre subito
  /// lo Start, per scattarne un altro.
  Future<void> _endAndRetakeSelfie(BuildContext context) async {
    final proSession = context.read<ProSession>();
    final navigator = Navigator.of(context);
    HapticFeedback.mediumImpact();
    await proSession.end();
    if (proSession.isOnline || !navigator.mounted) return;
    await _openStartSession(navigator.context);
  }

  /// Tocco su una persona: si apre la tendina "Cosa vuoi proporre?" e
  /// toccare una proposta manda la richiesta (2 tap in tutto). La
  /// preselezione e il segno "in linea con ciò che cerca" (dal suo intento
  /// pubblico) li decidono gli use case dietro `ProEncounters`. L'esito
  /// (partita o rifiutata, e perché) arriva da `CmpEncounterNoticeListener`:
  /// qui nessun "Richiesta inviata" prima di saperlo.
  Future<void> _chooseProposalAndRequest(
    BuildContext context,
    NearbyPerson person,
  ) async {
    final proEncounters = context.read<ProEncounters>();
    final proposal = await showProposalSheet(
      context,
      photoBytes: person.photoBytes,
      preselected: proEncounters.preselectedProposal,
      matchingTheirIntent: proEncounters.proposalMatchingIntent(person.intent),
    );
    if (proposal == null) return;
    HapticFeedback.lightImpact();
    proEncounters.sendRequest(person.id, proposal: proposal);
  }

  /// Per il chip della tile: "vuole conoscerti" se è lei ad aspettare una
  /// tua risposta, altrimenti (richiesta tua, o che sta partendo)
  /// "richiesta inviata". Se ce n'è una lo decide `hasRequested`, la stessa
  /// regola dello use case.
  static CmpNearbyRequestState _requestStateOf(
    ProEncounters proEncounters,
    String personId,
  ) {
    if (!proEncounters.hasRequested(personId)) {
      return CmpNearbyRequestState.none;
    }
    final awaitsYourAnswer = proEncounters.incomingRequests.any(
      (request) =>
          request.otherPersonId == personId &&
          request.status == EncounterRequestStatus.pending,
    );
    return awaitsYourAnswer
        ? CmpNearbyRequestState.received
        : CmpNearbyRequestState.sent;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proSession = context.watch<ProSession>();
    final session = proSession.session!;
    final proEncounters = context.watch<ProEncounters>();
    final pendingCount = proEncounters.pendingIncomingCount;
    final isDemo = DemoMode.isActive(context);

    return Scaffold(
      // Nella demo niente drawer: profilo, lingua e impostazioni sono del
      // mondo reale. Si esce dal banner della demo (o con End).
      drawer: isDemo ? null : const CmpAppDrawer(),
      appBar: AppBar(
        title: Text(l10n.nearby),
        actions: [
          // Puntini e niente tap mentre End è in corso: niente doppio tap.
          CmpEndButton(
            label: l10n.end_session,
            isBusy: proSession.isEnding,
            onPressed: () => _endSession(context),
          ),
        ],
      ),
      body: Column(
        children: [
          const CmpConnectionBanner(),
          if (isDemo) const CmpDemoNearbyNote(),
          Expanded(
            child: CmpPaywalledNearbyList(
              requestStateOf: (personId) =>
                  _requestStateOf(proEncounters, personId),
              onRequest: (person) => _chooseProposalAndRequest(context, person),
              onEndSession: () => _endSession(context),
              onRetakeSelfie: () => _endAndRetakeSelfie(context),
              actionsOf: (person) =>
                  CmpPersonSafetyMenuButton(personId: person.id),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CmpPhoto(image: MemoryImage(session.selfieBytes), size: 44),
            IconButton.filledTonal(
              icon: pendingCount == 0
                  ? const Icon(Icons.favorite_border)
                  : Badge(
                      label: Text('$pendingCount'),
                      child: const Icon(Icons.favorite_border),
                    ),
              tooltip: l10n.requests,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const UiEncounters())),
            ),
          ],
        ),
      ),
    );
  }
}
