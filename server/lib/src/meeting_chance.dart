/// Gli stessi tre stadi discreti del client Flutter (`NearbyPerson.meetingChance`
/// in `lib/features/nearby/domain/entities/nearby_person.dart`) — qui è dove
/// vengono davvero calcolati, non nel client.
enum MeetingChance { low, medium, high }

/// Sotto questo tempo di permanenza una persona resta invisibile in lista.
const visibilityThresholdMinutes = 1;

/// Bassa da 1 minuto, media da 3, alta da 5 — stesse soglie usate finora
/// dal finto datasource Flutter, ora spostate qui, lato server.
MeetingChance meetingChanceFor(Duration dwell) {
  final minutes = dwell.inMinutes;
  if (minutes >= 5) return MeetingChance.high;
  if (minutes >= 3) return MeetingChance.medium;
  return MeetingChance.low;
}
