import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/errors/failures.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';
import 'package:threemojo_app/features/profile/presentation/profile_labels.dart';
import 'package:threemojo_app/features/session/presentation/session_failure_texts.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

/// La UI sceglie il testo dal **tipo** di errore: ogni errore di Start e
/// del profilo ha il suo testo tradotto, mai il `message` tecnico.
void main() {
  for (final locale in AppLocalizations.supportedLocales) {
    test(
      '[${locale.languageCode}] every Start error has its own text',
      () async {
        final l10n = await AppLocalizations.delegate.load(locale);
        final failures = <Failure>[
          const SelfieMissingFailure(),
          const NoFaceInSelfieFailure(),
          const FaceCheckUnavailableFailure('PlatformException'),
          const SelfieCaptureFailure('Camera unavailable'),
          const ProfileMissingFailure(),
          const SensitiveDataConsentRequiredFailure(),
          const CacheFailure('Profile unreadable'),
        ];

        final texts = [
          for (final f in failures) SessionFailureTexts.of(l10n, f),
        ];

        expect(texts.toSet(), hasLength(failures.length));
        expect(texts, isNot(contains(l10n.action_failed_generic)));
        for (final f in failures) {
          expect(texts, isNot(contains(f.message)));
        }
      },
    );

    test('[${locale.languageCode}] every profile error has its own text, '
        'with the real language limit', () async {
      final l10n = await AppLocalizations.delegate.load(locale);
      final failures = <Failure>[
        const AdultConfirmationRequiredFailure(),
        const LookingForRequiredFailure(),
        const TooManyLanguagesFailure(Profile.maxLanguages),
        const UnsupportedLanguageFailure(),
        const SensitiveDataConsentRequiredFailure(),
        const CacheFailure('Profile not saved'),
      ];

      final texts = [for (final f in failures) ProfileLabels.failure(l10n, f)];

      expect(texts.toSet(), hasLength(failures.length));
      expect(texts, isNot(contains(l10n.action_failed_generic)));
      if (locale.languageCode != 'ar') {
        expect(
          ProfileLabels.failure(
            l10n,
            const TooManyLanguagesFailure(Profile.maxLanguages),
          ),
          contains('${Profile.maxLanguages}'),
        );
      }
    });
  }

  test('the notification texts exist in every language', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.background_location_notification_title, isNotEmpty);
      expect(l10n.background_location_notification_body, isNotEmpty);
      expect(l10n.background_location_notification_channel, isNotEmpty);
    }
  });
}
