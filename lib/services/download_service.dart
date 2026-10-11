import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/track.dart';
import 'device_id_service.dart';

enum StatusDownload { nenhum, baixando, baixado, erro }

/// Uma faixa já baixada: guarda tanto os dados da faixa (pra mostrar título
/// etc. sem precisar de rede) quanto o caminho do arquivo local.
class ArquivoBaixado {
  final Track track;
  final String caminho;

  const ArquivoBaixado({required this.track, required this.caminho});
}

/// Gerencia downloads de faixas pra ouvir offline: baixa o mp3 pra uma
/// pasta local do app (armazenamento privado do próprio app — não precisa
/// de nenhuma permissão especial de armazenamento), guarda o mapa em
/// shared_preferences (sobrevive a fechar/reabrir o app), e permite tocar
/// ou apagar faixas baixadas mesmo sem internet nenhuma. O PlayerService
/// consulta esse serviço e prefere o arquivo local (quando existir) em vez
/// de streaming.
class DownloadService extends ChangeNotifier {
  static const _prefsKeyMapa = 'sonora_downloads_mapa';

  final Map<String, ArquivoBaixado> _baixadas = {};
  final Map<String, double> _progresso = {};
  final Set<String> _comErro = {};

  DownloadService();

  /// Carrega o mapa de downloads já persistido. Precisa ser aguardado antes
  /// de runApp() — se o PlayerService restaurar o estado (e decidir entre
  /// tocar local ou via streaming) antes desse carregamento terminar, uma
  /// faixa baixada pode ser tratada como não-baixada logo na abertura do
  /// app (corrida entre os dois construtores).
  Future<void> inicializar() => _carregar();

  StatusDownload statusDe(String trackId) {
    if (_progresso.containsKey(trackId)) return StatusDownload.baixando;
    if (_baixadas.containsKey(trackId)) return StatusDownload.baixado;
    if (_comErro.contains(trackId)) return StatusDownload.erro;
    return StatusDownload.nenhum;
  }

  /// 0.0 a 1.0 enquanto está baixando (ou null se o tamanho total ainda
  /// não é conhecido) — null também quando não está baixando.
  double? progressoDe(String trackId) => _progresso[trackId];

  /// Caminho do arquivo local se a faixa já estiver baixada, ou null (usar
  /// streaming direto do Drive nesse caso).
  String? caminhoLocal(String trackId) => _baixadas[trackId]?.caminho;

  List<ArquivoBaixado> get todasBaixadas => _baixadas.values.toList();

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString(_prefsKeyMapa);
      if (bruto == null) return;

      final mapa = jsonDecode(bruto) as Map<String, dynamic>;
      for (final entrada in mapa.entries) {
        final dados = entrada.value as Map<String, dynamic>;
        final caminho = dados['path'] as String;
        // Confere se o arquivo ainda existe de verdade no aparelho —
        // pode ter sido apagado por fora do app (limpeza de espaço, etc).
        if (await File(caminho).exists()) {
          _baixadas[entrada.key] = ArquivoBaixado(
            track: Track(
              id: entrada.key,
              title: dados['title'] as String,
              sizeBytes: (dados['sizeBytes'] as num?)?.toInt() ?? 0,
            ),
            caminho: caminho,
          );
        }
      }
      notifyListeners();
    } catch (_) {
      // Mapa salvo corrompido — começa do zero, sem quebrar o app.
    }
  }

  Future<void> _salvarMapa() async {
    final prefs = await SharedPreferences.getInstance();
    final mapa = _baixadas.map((id, arq) => MapEntry(id, {
          'path': arq.caminho,
          'title': arq.track.title,
          'sizeBytes': arq.track.sizeBytes,
        }));
    await prefs.setString(_prefsKeyMapa, jsonEncode(mapa));
  }

  /// Baixa a faixa pro armazenamento do app. Não faz nada se já estiver
  /// baixada ou baixando no momento.
  Future<void> baixar(Track track) async {
    if (_baixadas.containsKey(track.id) || _progresso.containsKey(track.id)) {
      return;
    }

    _comErro.remove(track.id);
    _progresso[track.id] = 0.0;
    notifyListeners();

    final cliente = http.Client();
    try {
      final pasta = await _pastaDownloads();
      final destino = File('${pasta.path}/${track.id}.mp3');

      final appId = await DeviceIdService.getOrCreateDeviceId();
      final uri = Uri.parse(track.streamUrl(AppConstants.cloudRunBaseUrl, appId));
      final resposta = await cliente.send(http.Request('GET', uri));
      if (resposta.statusCode != 200) {
        throw Exception('HTTP ${resposta.statusCode}');
      }

      final total = resposta.contentLength ?? 0;
      var recebido = 0;
      var ultimoAviso = 0.0;
      final sink = destino.openWrite();

      await for (final pedaco in resposta.stream) {
        sink.add(pedaco);
        recebido += pedaco.length;
        if (total > 0) {
          final novo = recebido / total;
          _progresso[track.id] = novo;
          // Só avisa a tela a cada ~2%: com vários downloads ao mesmo
          // tempo, avisar a cada pedaço recebido travaria a lista.
          if (novo - ultimoAviso >= 0.02 || novo >= 1.0) {
            ultimoAviso = novo;
            notifyListeners();
          }
        }
      }
      await sink.close();

      _progresso.remove(track.id);
      _baixadas[track.id] = ArquivoBaixado(track: track, caminho: destino.path);
      // Persiste ANTES de avisar a UI — se o app fechar logo depois do
      // notifyListeners(), o download já está gravado no shared_preferences
      // e sobrevive a reabrir o app offline.
      await _salvarMapa();
      notifyListeners();
    } catch (_) {
      _progresso.remove(track.id);
      _comErro.add(track.id);
      notifyListeners();
    } finally {
      cliente.close();
    }
  }

  /// Remove o download: apaga o arquivo local e tira do mapa salvo. A
  /// faixa volta a tocar via streaming a partir daí.
  Future<void> remover(String trackId) async {
    final removido = _baixadas.remove(trackId);
    await _salvarMapa();
    notifyListeners();

    if (removido != null) {
      try {
        final arquivo = File(removido.caminho);
        if (await arquivo.exists()) await arquivo.delete();
      } catch (_) {
        // Não conseguiu apagar o arquivo físico — não é crítico, só fica
        // ocupando espaço; a faixa já não aparece mais como baixada.
      }
    }
  }

  Future<Directory> _pastaDownloads() async {
    final base = await getApplicationDocumentsDirectory();
    final pasta = Directory('${base.path}/downloads_offline');
    if (!await pasta.exists()) {
      await pasta.create(recursive: true);
    }
    return pasta;
  }
}
