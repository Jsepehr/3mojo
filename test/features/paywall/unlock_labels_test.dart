import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/paywall/domain/entities/unlock_time_left.dart';
import 'package:threemojo_app/features/paywall/presentation/unlock_labels.dart';
import 'package:threemojo_app/l10n/generated/app_localizations.dart';

UnlockTimeLeft _left(int wholeMinutes) => UnlockTimeLeft(
  wholeMinutes: wholeMinutes,
  isEndingSoon: wholeMinutes < 10,
  nextChangeIn: const Duration(minutes: 1),
);

void main() {
  test('short form in Italian and English: hours and minutes only', () async {
    final it = await AppLocalizations.delegate.load(const Locale('it'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    expect(UnlockLabels.timeLeft(it, _left(102)), '1 h 42 min');
    expect(UnlockLabels.timeLeft(it, _left(120)), '2 h');
    expect(UnlockLabels.timeLeft(it, _left(7)), '7 min');
    expect(UnlockLabels.timeLeft(it, _left(0)), 'meno di un minuto');
    expect(
      it.unlock_chip_label(UnlockLabels.timeLeft(it, _left(102))),
      'Sbloccato · ancora 1 h 42 min',
    );

    expect(UnlockLabels.timeLeft(en, _left(102)), '1 h 42 min');
    expect(UnlockLabels.timeLeft(en, _left(0)), 'less than a minute');
    expect(
      en.unlock_chip_label(UnlockLabels.timeLeft(en, _left(0))),
      'Unlocked · less than a minute left',
    );
  });

  test('spoken form, with plurals, for screen readers', () async {
    final it = await AppLocalizations.delegate.load(const Locale('it'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));

    expect(UnlockLabels.spokenTimeLeft(it, _left(102)), '1 ora e 42 minuti');
    expect(UnlockLabels.spokenTimeLeft(it, _left(61)), '1 ora e 1 minuto');
    expect(UnlockLabels.spokenTimeLeft(it, _left(120)), '2 ore');
    expect(
      UnlockLabels.spokenTimeLeft(en, _left(102)),
      '1 hour and 42 minutes',
    );
    expect(UnlockLabels.spokenTimeLeft(en, _left(1)), '1 minute');
    expect(UnlockLabels.spokenTimeLeft(en, _left(0)), 'less than a minute');
  });

  testWidgets('the expiry time follows the language (24 h vs 12 h)', (
    tester,
  ) async {
    final expiresAt = DateTime(2026, 10, 22, 23, 15, 40);
    final shown = <String, String>{};
    for (final locale in const [Locale('it'), Locale('en')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              shown[locale.languageCode] = UnlockLabels.expiryTime(
                context,
                expiresAt,
              );
              return const SizedBox();
            },
          ),
        ),
      );
    }

    expect(shown['it'], '23:15');
    expect(shown['en'], '11:15 PM');
  });
}
