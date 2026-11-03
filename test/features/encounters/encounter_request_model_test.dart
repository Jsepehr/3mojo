import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/session/domain/entities/meet_place.dart';
import 'package:threemojo_app/core/utils/photo_bytes_cache.dart';
import 'package:threemojo_app/features/encounters/data/models/encounter_request_model.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_proposal.dart';
import 'package:threemojo_app/features/encounters/domain/entities/encounter_request.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';

void main() {
  group('proposal', () {
    Map<String, dynamic> json(Object? proposal) => {
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'pending',
      'proposal': ?proposal,
    };

    test('reads a known code', () {
      expect(
        EncounterRequestModel.fromJson(json('drink')).proposal,
        EncounterProposal.drink,
      );
    });

    test('dance is part of the closed list', () {
      expect(
        EncounterRequestModel.tryFromJson(json('dance'))?.proposal,
        EncounterProposal.dance,
      );
    });

    test('an unknown code (newer server) or a missing one is getToKnow, '
        'without skipping the request', () {
      final unknown = EncounterRequestModel.tryFromJson(json('salsa'));
      final missing = EncounterRequestModel.tryFromJson(json(null));
      final notAString = EncounterRequestModel.tryFromJson(json(7));

      expect(unknown?.proposal, EncounterProposal.getToKnow);
      expect(missing?.proposal, EncounterProposal.getToKnow);
      expect(notAString?.proposal, EncounterProposal.getToKnow);
    });

    test('withStatus and withOtherSelfie keep it', () {
      final request = EncounterRequestModel.fromJson(json('chat'));

      expect(
        request.withStatus(EncounterRequestStatus.declined).proposal,
        EncounterProposal.chat,
      );
      expect(
        request.withOtherSelfie(Uint8List.fromList([1])).proposal,
        EncounterProposal.chat,
      );
    });
  });

  test('reads what the other person shows on their profile', () {
    final request = EncounterRequestModel.fromJson({
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'pending',
      'otherPlace': 'bar',
      'otherLanguages': ['it', 'en'],
      'otherGender': 'nonBinary',
    });

    expect(request.otherPlace, MeetPlace.bar);
    expect(request.otherLanguages, ['it', 'en']);
    expect(request.otherVisibleGender, Gender.nonBinary);
  });

  test('missing or unknown profile values are simply not shown', () {
    final request = EncounterRequestModel.fromJson({
      'id': 'req-1',
      'otherPersonId': 'p',
      'status': 'pending',
      'otherPlace': 'something-new',
    });

    expect(request.otherPlace, MeetPlace.other);
    expect(request.otherLanguages, isEmpty);
    expect(request.otherVisibleGender, isNull);
  });

  test('withStatus keeps the profile details', () {
    const request = EncounterRequestModel(
      id: 'req-1',
      otherPersonId: 'p',
      status: EncounterRequestStatus.pending,
      otherPlace: MeetPlace.cafe,
      otherLanguages: ['it'],
    );

    final accepted = request.withStatus(EncounterRequestStatus.accepted);

    expect(accepted.status, EncounterRequestStatus.accepted);
    expect(accepted.otherPlace, MeetPlace.cafe);
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
