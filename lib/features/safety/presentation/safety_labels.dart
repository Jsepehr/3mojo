import '/core/errors/failures.dart';
import '/l10n/generated/app_localizations.dart';
import '../domain/entities/report_reason.dart';
import '../domain/entities/safety_rejection.dart';
import '../domain/usecases/report_person_usecase.dart';

/// Testi di "Blocca"/"Segnala": i motivi della segnalazione e gli esiti,
/// scelti dal **tipo** (di `Failure`, di rifiuto) — mai da un `message`.
/// Non è un widget: solo la traduzione da valori di dominio a testo.
class SafetyLabels {
  const SafetyLabels._();

  static String reason(AppLocalizations l10n, ReportReason reason) =>
      switch (reason) {
        ReportReason.fakePhoto => l10n.report_reason_fake_photo,
        ReportReason.inappropriatePhoto =>
          l10n.report_reason_inappropriate_photo,
        ReportReason.harassment => l10n.report_reason_harassment,
        ReportReason.underage => l10n.report_reason_underage,
        ReportReason.spam => l10n.report_reason_spam,
        ReportReason.other => l10n.report_reason_other,
      };

  /// Un blocco o una segnalazione non partiti.
  static String failure(AppLocalizations l10n, Failure failure) =>
      switch (failure) {
        TooManyReportsFailure(:final maxReports) => l10n.too_many_reports(
          maxReports,
        ),
        ConnectionFailure() => l10n.action_not_sent_offline,
        _ => l10n.action_failed_generic,
      };

  /// Un blocco o una segnalazione rifiutati dal server.
  static String rejection(AppLocalizations l10n, SafetyRejection rejection) =>
      switch ((rejection.action, rejection.reason)) {
        (SafetyAction.block, SafetyRejectionReason.unknownPerson) =>
          l10n.block_rejected_person_gone,
        (SafetyAction.report, SafetyRejectionReason.unknownPerson) =>
          l10n.report_rejected_person_gone,
        (SafetyAction.report, SafetyRejectionReason.tooManyReports) =>
          l10n.too_many_reports(ReportPersonUseCase.maxReportsPerSession),
        (SafetyAction.report, _) => l10n.report_rejected_generic,
        (SafetyAction.block, _) => l10n.action_failed_generic,
      };
}
