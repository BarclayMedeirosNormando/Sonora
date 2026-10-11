import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import 'api_service.dart';
import 'device_id_service.dart';
import 'download_service.dart';

/// Modo offline POR PLAYLIST: quando ligado, baixa todas as faixas da
/// playlist (via DownloadService) e, dali em diante, baixa sozinho as que
/// forem adicionadas depois na curadoria (e apaga as que forem removidas).
///
/// Downloads só acontecem no Wi-Fi (ou cabo) pra não gastar o pacote de
/// dados do usuário -- se ligar o modo offline no 4G/5G, fica marcado e o
/// download começa assim que o aparelho entrar num Wi-Fi. O usuário pode
/// ligar a chave "baixar também com dados móveis" (desligada por padrão).
/// Baixa 3 faixas ao mesmo tempo. Só baixa com o
/// app aberto (não existe serviço de download em segundo plano).
///
/// Persistido: só { playlistId: [fileId, ...] } das playlists com o modo
/// ligado. A lista completa de faixas (pra baixar) é refeita a cada
/// sincronização, que roda ao abrir a Home e ao abrir a playlist.
class OfflinePlaylistService extends ChangeNotifier {
  static const _prefsKey = 'sonora_offline_playlists';
  static const _prefsKeyDados = 'sonora_offline_usar_dados';

  /// Quantas faixas baixam ao mesmo tempo.
  static const _paralelo = 3;

  final DownloadService _downloads;

  /// playlistId -> fileIds da última sincronização (persistido).
  final Map<String, List<String>> _ativas = {};

  /// playlistId -> faixas completas da última sincronização (só memória).
  final Map<String, List<Track>> _faixasDe = {};

  bool _processando = false;
  bool _temWifi = false;
  bool _temRede = true;
  bool _usarDados = false;
  StreamSubscription<List<ConnectivityResult>>? _assinatura;

  OfflinePlaylistService(this._downloads);

  /// Wi-Fi (ou cabo) disponível agora -- único caso em que baixa.
  bool get temWifi => _temWifi;

  /// Qualquer conexão (Wi-Fi ou dados móveis). Falso = modo avião/sem sinal.
  bool get temRede => _temRede;

  /// Chave "baixar também com dados móveis" (desligada por padrão).
  bool get usarDadosMoveis => _usarDados;

  /// Pode baixar agora: Wi-Fi/cabo sempre; dados móveis só se o usuário
  /// ligou a chave.
  bool get podeBaixarAgora => _temWifi || (_usarDados && _temRede);

  /// Liga/desliga o download com dados móveis. Ao ligar, retoma o que
  /// estiver pendente.
  Future<void> definirUsarDadosMoveis(bool valor) async {
    if (_usarDados == valor) return;
    _usarDados = valor;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyDados, valor);
    } catch (_) {
      // Não salvou agora -- vale só até fechar o app.
    }
    notifyListeners();
    if (valor) _processar();
  }

  bool estaAtiva(String playlistId) => _ativas.containsKey(playlistId);

  int totalDe(String playlistId) => _ativas[playlistId]?.length ?? 0;

  int baixadasDe(String playlistId) {
    final ids = _ativas[playlistId];
    if (ids == null) return 0;
    return ids
        .where((id) => _downloads.statusDe(id) == StatusDownload.baixado)
        .length;
  }

  bool completa(String playlistId) {
    final total = totalDe(playlistId);
    return total > 0 && baixadasDe(playlistId) >= total;
  }

  /// Carrega as playlists com modo offline ligado e começa a acompanhar a
  /// conectividade. Nunca lança -- falha aqui só desliga o extra.
  Future<void> inicializar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString(_prefsKey);
      if (bruto != null) {
        final mapa = jsonDecode(bruto) as Map<String, dynamic>;
        for (final e in mapa.entries) {
          _ativas[e.key] = (e.value as List).cast<String>().toList();
        }
      }
      _usarDados = prefs.getBool(_prefsKeyDados) ?? false;
    } catch (_) {
      // Estado salvo corrompido -- começa sem nenhuma playlist offline.
    }

    try {
      final conectividade = Connectivity();
      _aplicarConectividade(await conectividade.checkConnectivity(), notificar: false);
      _assinatura = conectividade.onConnectivityChanged.listen(_aplicarConectividade);
    } catch (_) {
      // Sem como saber a rede: assume que tem internet, mas NÃO assume
      // Wi-Fi (conservador -- não baixa nada por conta própria).
      _temRede = true;
      _temWifi = false;
    }
  }

  void _aplicarConectividade(List<ConnectivityResult> resultado, {bool notificar = true}) {
    final wifi = resultado.contains(ConnectivityResult.wifi) ||
        resultado.contains(ConnectivityResult.ethernet);
    final podiaBaixar = podeBaixarAgora;
    _temWifi = wifi;
    _temRede = resultado.any((c) => c != ConnectivityResult.none);
    if (notificar) notifyListeners();
    if (!podiaBaixar && podeBaixarAgora) _processar();
  }

  /// Liga o modo offline da playlist e começa a baixar (se estiver no Wi-Fi).
  Future<void> ativar(Playlist playlist) async {
    _registrar(playlist);
    await _salvar();
    notifyListeners();
    _processar();
  }

  /// Desliga o modo offline e apaga do aparelho as faixas dessa playlist
  /// (as que não estiverem também em outra playlist com o modo ligado).
  Future<void> desativar(String playlistId) async {
    final ids = _ativas.remove(playlistId) ?? const <String>[];
    _faixasDe.remove(playlistId);
    await _removerOrfas(ids);
    await _salvar();
    notifyListeners();
  }

  /// Atualiza uma playlist com o modo ligado com o que veio da rede: baixa
  /// as faixas novas e apaga as que saíram da curadoria.
  Future<void> sincronizar(Playlist playlist) async {
    if (!estaAtiva(playlist.id)) return;
    final antigos = _ativas[playlist.id] ?? const <String>[];
    _registrar(playlist);
    final atuais = _ativas[playlist.id]!.toSet();
    await _removerOrfas(antigos.where((id) => !atuais.contains(id)));
    await _salvar();
    notifyListeners();
    _processar();
  }

  /// Chamado pela Home ao carregar: reavalia todas as playlists com o modo
  /// ligado (busca a lista atual de faixas de cada uma).
  Future<void> sincronizarTodas(List<PlaylistResumo> resumos) async {
    if (_ativas.isEmpty) return;
    try {
      final appId = await DeviceIdService.getOrCreateDeviceId();
      final idsAtuais = resumos.map((r) => r.id).toSet();

      // Playlist que o usuário não recebe mais: desliga e apaga.
      for (final id in _ativas.keys.toList()) {
        if (!idsAtuais.contains(id)) await desativar(id);
      }

      for (final r in resumos) {
        if (!estaAtiva(r.id)) continue;
        try {
          await sincronizar(await ApiService.obterPlaylist(r.id, appId));
        } catch (_) {
          // Sem rede agora -- tenta de novo na próxima abertura.
        }
      }
    } catch (_) {
      // Extra: nunca pode quebrar a Home.
    }
  }

  void _registrar(Playlist playlist) {
    _ativas[playlist.id] = playlist.faixas.map((f) => f.fileId).toList();
    _faixasDe[playlist.id] = playlist.faixas
        .map(
          (f) => Track(
            id: f.fileId,
            title: f.nome,
            paiId: f.albumId,
            capaId: f.capaId,
            albumNome: f.albumNome,
          ),
        )
        .toList();
  }

  bool _emUso(String fileId) => _ativas.values.any((ids) => ids.contains(fileId));

  Future<void> _removerOrfas(Iterable<String> candidatos) async {
    for (final id in candidatos.toList()) {
      if (_emUso(id)) continue;
      if (_downloads.statusDe(id) == StatusDownload.baixado) {
        await _downloads.remover(id);
      }
    }
  }

  Future<void> _salvar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_ativas));
    } catch (_) {
      // Não conseguiu salvar agora -- tenta de novo na próxima mudança.
    }
  }

  Track? _proximaPendente(Set<String> jaTentadas) {
    for (final entrada in _faixasDe.entries) {
      if (!_ativas.containsKey(entrada.key)) continue;
      for (final faixa in entrada.value) {
        if (jaTentadas.contains(faixa.id)) continue;
        final status = _downloads.statusDe(faixa.id);
        if (status == StatusDownload.baixado || status == StatusDownload.baixando) {
          continue;
        }
        return faixa;
      }
    }
    return null;
  }

  /// Baixa tudo que está pendente nas playlists com o modo ligado, 3 faixas
  /// ao mesmo tempo, enquanto puder baixar (Wi-Fi, ou dados móveis se o
  /// usuário ligou a chave). Só uma execução por vez.
  Future<void> _processar() async {
    if (_processando) return;
    _processando = true;
    notifyListeners();

    final jaTentadas = <String>{};
    var falhasSeguidas = 0;
    var parar = false;

    Future<void> trabalhador() async {
      while (!parar && podeBaixarAgora) {
        final proxima = _proximaPendente(jaTentadas);
        if (proxima == null) break;
        jaTentadas.add(proxima.id);

        await _downloads.baixar(proxima);

        if (_downloads.statusDe(proxima.id) == StatusDownload.erro) {
          // 3 erros seguidos = provavelmente sem rede de verdade / sem
          // espaço; para todos e tenta de novo na próxima sincronização.
          if (++falhasSeguidas >= 3) parar = true;
        } else {
          falhasSeguidas = 0;
          // A playlist pode ter sido desligada enquanto essa faixa baixava.
          if (!_emUso(proxima.id)) await _downloads.remover(proxima.id);
        }
        notifyListeners();
      }
    }

    try {
      await Future.wait(List.generate(_paralelo, (_) => trabalhador()));
    } finally {
      _processando = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _assinatura?.cancel();
    super.dispose();
  }
}
