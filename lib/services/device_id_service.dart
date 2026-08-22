import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';

/// Gera e persiste o App_ID (UUID) usado para liberar o acesso ao app,
/// no mesmo padrão já usado no BarclayFlix.
class DeviceIdService {
  static const _uuid = Uuid();

  /// Retorna o App_ID salvo localmente, gerando um novo na primeira vez.
  static Future<String> getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(AppConstants.prefsDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final newId = _uuid.v4();
    await prefs.setString(AppConstants.prefsDeviceIdKey, newId);
    return newId;
  }
}
