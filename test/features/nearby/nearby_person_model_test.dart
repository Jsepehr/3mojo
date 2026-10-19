import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:threemojo_app/features/nearby/data/models/nearby_person_model.dart';
import 'package:threemojo_app/features/nearby/domain/entities/nearby_person.dart';
import 'package:threemojo_app/features/profile/domain/entities/profile.dart';

void main() {
  test('reads the new protocol: no distance, the lock flag, decoded photo', () {
    final person = NearbyPersonModel.fromJson({
      'personId': 'p',
      'meetingChance': 'medium',
      'locked': false,
      'selfieBase64': base64Encode([1, 2, 3]),
      'intent': 'friendship',
      'languages': ['it'],
      'gender': 'female',
    });

    expect(person.id, 'p');
    expect(person.meetingChance, MeetingChance.medium);
    expect(person.isLocked, isFalse);
    expect(person.photoBytes, [1, 2, 3]);
    expect(person.intent, MeetIntent.friendship);
    expect(person.visibleGender, Gender.female);
  });

  test('a malformed photo is just no photo', () {
    final person = NearbyPersonModel.fromJson({
      'personId': 'p',
      'meetingChance': 'low',
      'selfieBase64': '%%% not base64',
    });

    expect(person.photoBytes, isNull);
  });

  test('missing id or unknown chance: skipped by tryFromJson', () {
    expect(NearbyPersonModel.tryFromJson({'meetingChance': 'low'}), isNull);
    expect(
      NearbyPersonModel.tryFromJson({'personId': 'p', 'meetingChance': 'x'}),
      isNull,
    );
  });
}
