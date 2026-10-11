import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

/// Gera e persiste o App_ID usado para liberar o acesso ao app.
///
/// CÓDIGO CURTO (17/09/2026): antes era um UUID completo (36 caracteres,
/// ex. "a3f9c2e1-8b4d-4a2e-9c1f-7d6e5b4a3c2f") -- praticamente impossível
/// de decorar/ditar por telefone. Trocado por um código de 6 caracteres
/// (ex. "7XKP9Q"), sorteado de um alfabeto de 32 símbolos sem caracteres
/// ambíguos (sem 0/O, 1/I/L) -- ainda com ~1 bilhão de combinações
/// possíveis, sobra pra qualquer volume real de usuários do Sonora.
/// App_IDs já gerados (formato UUID antigo) continuam funcionando
/// normalmente -- essa mudança só afeta instalações novas a partir de
/// agora, não precisa de migração.
class DeviceIdService {
  static const _alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _tamanhoCodigo = 6;

  // Cache em memoria (01/09/2026): ver histórico do projeto -- evita
  // reler o SharedPreferences toda vez que algum serviço pede o appId.
  static String? _cache;

  /// App_ID já carregado em memória, de forma SÍNCRONA -- usado pra montar
  /// URLs de capa dentro de build() (que não pode esperar um Future).
  /// Vazio só antes da primeira chamada a getOrCreateDeviceId(), que a
  /// tela de validação já faz antes de qualquer capa aparecer.
  static String get idEmCache => _cache ?? '';

  static String _gerarCodigo() {
    final random = Random.secure();
    return List.generate(
      _tamanhoCodigo,
      (_) => _alfabeto[random.nextInt(_alfabeto.length)],
    ).join();
  }

  /// Retorna o App_ID salvo localmente, gerando um novo na primeira vez.
  static Future<String> getOrCreateDeviceId() async {
    final cache = _cache;
    if (cache != null) return cache;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(AppConstants.prefsDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _cache = existing;
      return existing;
    }
    final newId = _gerarCodigo();
    await prefs.setString(AppConstants.prefsDeviceIdKey, newId);
    _cache = newId;
    return newId;
  }
}
