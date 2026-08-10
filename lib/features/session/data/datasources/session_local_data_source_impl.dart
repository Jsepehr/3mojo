import 'package:shared_preferences/shared_preferences.dart';

import '/features/session/domain/entities/online_session.dart';
import 'session_local_data_source.dart';

/// Implementazione **reale**: salva selfie/genere/preferenza con
/// `shared_preferences`. `endSession` li rimuove — nessuna traccia resta
/// tra un End e il prossimo Start.
class SessionLocalDataSourceImpl implements SessionLocalDataSource {
  static const String _selfiePathKey = 'session_selfie_path';
  static const String _genderKey = 'session_gender';
  static const String _genderPreferenceKey = 'session_gender_preference';

  @override
  Future<OnlineSession?> getCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final selfiePath = prefs.getString(_selfiePathKey);
    final genderName = prefs.getString(_genderKey);
    final genderPreferenceName = prefs.getString(_genderPreferenceKey);

    if (selfiePath == null ||
        genderName == null ||
        genderPreferenceName == null) {
      return null;
    }

    return OnlineSession(
      selfiePath: selfiePath,
      gender: Gender.values.byName(genderName),
      genderPreference: GenderPreference.values.byName(genderPreferenceName),
    );
  }

  @override
  Future<OnlineSession> startSession(OnlineSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selfiePathKey, session.selfiePath);
    await prefs.setString(_genderKey, session.gender.name);
    await prefs.setString(_genderPreferenceKey, session.genderPreference.name);
    return session;
  }

  @override
  Future<void> endSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_selfiePathKey);
    await prefs.remove(_genderKey);
    await prefs.remove(_genderPreferenceKey);
  }
}
