import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/core/utils/photo_bytes_cache.dart';
import 'package:threemojo_app/features/encounters/data/models/encounter_request_model.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';

void main() {
  test('reads what the other person shows on their profile', () {
    final request = EncounterRequestModel.fromJson({
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'pending',
      'otherIntent': 'friendship',
      'otherLanguages': ['it', 'en'],
      'otherGender': 'nonBinary',
    });

    expect(request.otherIntent, MeetIntent.friendship);
    expect(request.otherLanguages, ['it', 'en']);
    expect(request.otherVisibleGender, Gender.nonBinary);
  });

  test('missing or unknown profile values are simply not shown', () {
    final request = EncounterRequestModel.fromJson({
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'pending',
      'otherIntent': 'something-new',
    });

    expect(request.otherIntent, isNull);
    expect(request.otherLanguages, isEmpty);
    expect(request.otherVisibleGender, isNull);
  });

  test('withStatus keeps the profile details', () {
    const request = EncounterRequestModel(
      id: 'req-1',
      otherPersonId: 'p',
      status: EncounterRequestStatus.pending,
      otherIntent: MeetIntent.chat,
      otherLanguages: ['it'],
    );

    final accepted = request.withStatus(EncounterRequestStatus.accepted);

    expect(accepted.status, EncounterRequestStatus.accepted);
    expect(accepted.otherIntent, MeetIntent.chat);
    expect(accepted.otherLanguages, ['it']);
  });

  test('an unknown status skips that request instead of failing the whole '
      'snapshot', () {
    expect(
      EncounterRequestModel.tryFromJson({
        'id': 'req-1',
        'otherPersonId': 'p',
        'status': 'snoozed',
      }),
      isNull,
    );
    expect(EncounterRequestModel.tryFromJson('not a map'), isNull);
    expect(
      () =>
          EncounterRequestModel.fromJson({'id': 'req-1', 'status': 'pending'}),
      throwsFormatException,
    );
  });

  test('the selfie is decoded once; malformed base64 means no photo, never '
      'an exception', () {
    final photos = PhotoBytesCache();
    final selfie = base64Encode([0xFF, 0xD8, 0xFF, 0xD9]);
    Map<String, dynamic> json(String photo) => {
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'accepted',
      'otherSelfieBase64': photo,
    };

    final first = EncounterRequestModel.fromJson(json(selfie), photos: photos);
    final second = EncounterRequestModel.fromJson(json(selfie), photos: photos);
    final broken = EncounterRequestModel.fromJson(json('%%%'), photos: photos);

    expect(first.otherSelfieBytes, [0xFF, 0xD8, 0xFF, 0xD9]);
    expect(identical(first.otherSelfieBytes, second.otherSelfieBytes), isTrue);
    expect(broken.otherSelfieBytes, isNull);
  });
}
