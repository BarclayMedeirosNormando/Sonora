import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/track.dart';

/// Estado e controle da reprodução: fila de faixas, play/pause, avançar/
/// voltar, reordenar fila, "tocar a seguir", sleep timer e restaurar de
/// onde parou.
class PlayerService extends ChangeNotifier with WidgetsBindingObserver {
  static const _prefsKeyEstado = 'sonora_estado_player';

  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource? _playlist;

  final List<Track> _fila = [];
  int _indiceAtual = -1;

  Timer? _sleepTimer;
  DateTime? _sleepFimEm;

  PlayerService() {
    WidgetsBinding.instance.addObserver(this);

    _player.playerStateStream.listen((_) => notifyListeners());
    _player.currentIndexStream.listen((index) {
      if (index != null && index != _indiceAtual) {
        _indiceAtual = index;
        notifyListeners();
      }
      _salvarEstado();
    });

    _restaurarEstado();
  }

  Track? get faixaAtual =>
      (_indiceAtual >= 0 && _indiceAtual < _fila.length) ? _fila[_indiceAtual] : null;

  bool get tocando => _player.playing;
  Stream<Duration> get posicaoStream => _player.positionStream;
  Duration get duracao => _player.duration ?? Duration.zero;

  LoopMode get modoRepeticao => _player.loopMode;
  bool get modoAleatorio => _player.shuffleModeEnabled;
  double get velocidade => _player.speed;

  /// Fila atual (cópia — usar reordenarFila/tocarASeguir pra mexer nela).
  List<Track> get fila => List.unmodifiable(_fila);
  int get indiceAtual => _indiceAtual;

  bool get sleepTimerAtivo => _sleepFimEm != null;
  Duration? get sleepRestante =>
      _sleepFimEm == null ? null : _sleepFimEm!.difference(DateTime.now());

  /// Começa a tocar uma fila de faixas a partir de um índice (ex: as faixas
  /// da pasta atual, começando na que o usuário tocou).
  Future<void> tocarFila(List<Track> faixas, int indiceInicial) async {
    _fila
      ..clear()
      ..addAll(faixas);
    _indiceAtual = indiceInicial;
    notifyListeners();

    _playlist = ConcatenatingAudioSource(
      children: faixas
          .map((f) => AudioSource.uri(Uri.parse(f.streamUrl(AppConstants.driveApiKey))))
          .toList(),
    );

    await _player.setAudioSource(_playlist!, initialIndex: indiceInicial);
    await _player.play();
    _salvarEstado();
  }

  Future<void> alternarPlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _salvarEstado();
  }

  Future<void> proxima() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> anterior() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  Future<void> seekPara(Duration posicao) async {
    await _player.seek(posicao);
    _salvarEstado();
  }

  /// Alterna entre desligado -> repetir tudo -> repetir uma faixa -> desligado.
  Future<void> alternarRepeticao() async {
    final proximo = switch (_player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(proximo);
    notifyListeners();
  }

  /// Liga/desliga o modo aleatório. Ao ligar, embaralha a ordem da fila.
  Future<void> alternarAleatorio() async {
    final ligar = !_player.shuffleModeEnabled;
    if (ligar) await _player.shuffle();
    await _player.setShuffleModeEnabled(ligar);
    notifyListeners();
  }

  /// Velocidades disponíveis pra alternar (botão "1x", "1.5x" etc no player).
  static const List<double> velocidadesDisponiveis = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75];

  Future<void> alternarVelocidade() async {
    final indiceAtualVel = velocidadesDisponiveis.indexOf(_player.speed);
    final proximaVelocidade = velocidadesDisponiveis[
        (indiceAtualVel + 1) % velocidadesDisponiveis.length];
    await _player.setSpeed(proximaVelocidade);
    notifyListeners();
  }

  // ===== Fila: reordenar e "tocar a seguir" =====

  /// Move uma faixa da fila de [indiceAntigo] pra [novoIndice], seguindo a
  /// semântica do ReorderableListView (novoIndice já considera a lista
  /// depois de remover o item da posição antiga).
  Future<void> reordenarFila(int indiceAntigo, int novoIndice) async {
    if (_playlist == null) return;
    var destino = novoIndice;
    if (destino > indiceAntigo) destino -= 1;
    if (destino == indiceAntigo) return;

    await _playlist!.move(indiceAntigo, destino);
    final item = _fila.removeAt(indiceAntigo);
    _fila.insert(destino, item);

    if (_indiceAtual == indiceAntigo) {
      _indiceAtual = destino;
    } else if (indiceAntigo < _indiceAtual && destino >= _indiceAtual) {
      _indiceAtual -= 1;
    } else if (indiceAntigo > _indiceAtual && destino <= _indiceAtual) {
      _indiceAtual += 1;
    }

    notifyListeners();
    _salvarEstado();
  }

  /// Insere a faixa logo depois da que está tocando agora (ou começa a
  /// tocar ela, se não tiver nada tocando ainda).
  Future<void> tocarASeguir(Track track) async {
    if (_playlist == null || _fila.isEmpty) {
      await tocarFila([track], 0);
      return;
    }

    final posicaoInsercao = _indiceAtual + 1;
    await _playlist!.insert(
      posicaoInsercao,
      AudioSource.uri(Uri.parse(track.streamUrl(AppConstants.driveApiKey))),
    );
    _fila.insert(posicaoInsercao, track);
    notifyListeners();
    _salvarEstado();
  }

  // ===== Sleep timer =====

  void ativarSleepTimer(Duration duracao) {
    _sleepTimer?.cancel();
    _sleepFimEm = DateTime.now().add(duracao);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sleepFimEm == null) return;
      if (DateTime.now().isAfter(_sleepFimEm!)) {
        _player.pause();
        cancelarSleepTimer();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelarSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepFimEm = null;
    notifyListeners();
  }

  // ===== Continuar de onde parou =====

  Future<void> _salvarEstado() async {
    if (_fila.isEmpty || _indiceAtual < 0) return;
    final prefs = await SharedPreferences.getInstance();
    final estado = {
      'fila': _fila.map((t) => t.toLocalJson()).toList(),
      'indice': _indiceAtual,
      'posicaoMs': _player.position.inMilliseconds,
    };
    await prefs.setString(_prefsKeyEstado, jsonEncode(estado));
  }

  /// Carrega a fila/posição salvas e deixa pronto pra continuar — sem
  /// iniciar a reprodução sozinho, só quando o usuário apertar play.
  Future<void> _restaurarEstado() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bruto = prefs.getString(_prefsKeyEstado);
      if (bruto == null) return;

      final estado = jsonDecode(bruto) as Map<String, dynamic>;
      final listaFaixas = (estado['fila'] as List)
          .map((e) => Track.fromLocalJson(e as Map<String, dynamic>))
          .toList();
      final indice = estado['indice'] as int? ?? 0;
      final posicaoMs = estado['posicaoMs'] as int? ?? 0;

      if (listaFaixas.isEmpty || indice < 0 || indice >= listaFaixas.length) return;

      _fila
        ..clear()
        ..addAll(listaFaixas);
      _indiceAtual = indice;

      _playlist = ConcatenatingAudioSource(
        children: listaFaixas
            .map((f) => AudioSource.uri(Uri.parse(f.streamUrl(AppConstants.driveApiKey))))
            .toList(),
      );

      await _player.setAudioSource(
        _playlist!,
        initialIndex: indice,
        initialPosition: Duration(milliseconds: posicaoMs),
      );
      notifyListeners();
    } catch (_) {
      // Estado salvo inválido/corrompido — ignora e começa do zero.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _salvarEstado();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _player.dispose();
    super.dispose();
  }
}
