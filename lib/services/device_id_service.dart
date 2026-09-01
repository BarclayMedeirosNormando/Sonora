import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';

/// Gera e persiste o App_ID (UUID) usado para liberar o acesso ao app,
/// no mesmo padrão já usado no BarclayFlix.
class DeviceIdService {
  static const _uuid = Uuid();

  // Cache em memoria (01/09/2026): antes cada servico que precisava do
  // appId (PlayerService, DownloadService, LibraryCacheService, etc.)
  // chamava getOrCreateDeviceId() direto, e o PlayerService ainda
  // mantinha seu proprio cache local pra evitar reler o SharedPreferences
  // toda hora. Centralizando aqui, TODO mundo se beneficia do cache com
  // uma unica fonte de verdade, sem duplicar a logica em cada servico.
  static String? _cache;

  /// Retorna o App_ID salvo localmente, gerando um novo na primeira vez.
  /// A partir da segunda chamada (de qualquer lugar do app), devolve
  /// direto da memoria, sem tocar no SharedPreferences de novo.
  static Future<String> getOrCreateDeviceId() async {
    final cache = _cache;
    if (cache != null) return cache;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(AppConstants.prefsDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _cache = existing;
      return existing;
    }
    final newId = _uuid.v4();
    await prefs.setString(AppConstants.prefsDeviceIdKey, newId);
    _cache = newId;
    return newId;
  }
}
