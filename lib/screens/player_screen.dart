import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/player_service.dart';
import 'fila_screen.dart';

/// Tela cheia do player: capa, título, progresso e controles.
class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  String _formatarDuracao(Duration d) {
    final minutos = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final segundos = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutos:$segundos';
  }

  void _mostrarSleepTimer(BuildContext context, PlayerService player) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Sleep timer'),
        children: [
          if (player.sleepTimerAtivo)
            SimpleDialogOption(
              onPressed: () {
                player.cancelarSleepTimer();
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar timer ativo'),
            ),
          for (final minutos in [10, 20, 30, 45, 60])
            SimpleDialogOption(
              onPressed: () {
                player.ativarSleepTimer(Duration(minutes: minutos));
                Navigator.of(context).pop();
              },
              child: Text('$minutos minutos'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tocando agora'),
        actions: [
          Consumer<PlayerService>(
            builder: (context, player, _) => IconButton(
              icon: Icon(
                player.sleepTimerAtivo ? Icons.bedtime : Icons.bedtime_outlined,
                color: player.sleepTimerAtivo ? AppTheme.accent : null,
              ),
              tooltip: 'Sleep timer',
              onPressed: () => _mostrarSleepTimer(context, player),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Fila',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FilaScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<PlayerService>(
        builder: (context, player, _) {
          final faixa = player.faixaAtual;
          if (faixa == null) {
            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.surfaceHigh, AppTheme.background],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Center(
                child: Text(
                  'Nada tocando',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }

          final capaUrl = faixa.capaUrl(AppConstants.driveApiKey);
          const placeholder = Center(
            child: Icon(Icons.album, size: 96, color: AppTheme.textSecondary),
          );

          return _FundoDinamico(
            capaUrl: capaUrl,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'capa-${faixa.id}',
                        child: Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceHigh,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: capaUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: capaUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 440,
                                    placeholder: (context, url) => placeholder,
                                    errorWidget: (context, url, error) => placeholder,
                                  )
                                : placeholder,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        faixa.displayTitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (faixa.albumNome.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          faixa.albumNome,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      StreamBuilder<Duration>(
                        stream: player.posicaoStream,
                        builder: (context, snapshot) {
                          final posicao = snapshot.data ?? Duration.zero;
                          final duracao = player.duracao;
                          final totalMs = duracao.inMilliseconds > 0
                              ? duracao.inMilliseconds.toDouble()
                              : 1.0;
                          final atualMs = posicao.inMilliseconds
                              .clamp(0, totalMs.toInt())
                              .toDouble();

                          return Column(
                            children: [
                              Slider(
                                value: atualMs,
                                max: totalMs,
                                activeColor: AppTheme.accent,
                                inactiveColor: AppTheme.surfaceHigh,
                                onChanged: (valor) {
                                  player.seekPara(Duration(milliseconds: valor.toInt()));
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatarDuracao(posicao),
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _formatarDuracao(duracao),
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_previous, color: AppTheme.textPrimary),
                            onPressed: player.anterior,
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 64,
                            icon: Icon(
                              player.tocando ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: AppTheme.accent,
                            ),
                            onPressed: player.alternarPlayPause,
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_next, color: AppTheme.textPrimary),
                            onPressed: player.proxima,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: player.modoAleatorio ? AppTheme.accent : AppTheme.textSecondary,
                            ),
                            onPressed: player.alternarAleatorio,
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              switch (player.modoRepeticao) {
                                LoopMode.one => Icons.repeat_one,
                                _ => Icons.repeat,
                              },
                              color: player.modoRepeticao == LoopMode.off
                                  ? AppTheme.textSecondary
                                  : AppTheme.accent,
                            ),
                            onPressed: player.alternarRepeticao,
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: player.alternarVelocidade,
                            child: Text(
                              '${player.velocidade.toStringAsFixed(player.velocidade == player.velocidade.roundToDouble() ? 0 : 2)}x',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (player.sleepTimerAtivo) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Sleep timer: ${player.sleepRestante!.inMinutes + 1} min restantes',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Fundo com gradiente que muda de cor conforme a capa do álbum tocando —
/// extrai a cor dominante da capa (API nativa do Flutter, sem depender de
/// pacote externo) e anima a transição entre uma faixa e outra. Cai pro
/// gradiente cinza padrão enquanto extrai (ou se não tiver capa/der erro).
/// Cor extraída fica em cache em memória por URL, então trocar entre
/// faixas já vistas antes é instantâneo.
class _FundoDinamico extends StatefulWidget {
  final String? capaUrl;
  final Widget child;

  const _FundoDinamico({required this.capaUrl, required this.child});

  @override
  State<_FundoDinamico> createState() => _FundoDinamicoState();
}

class _FundoDinamicoState extends State<_FundoDinamico> {
  static final Map<String, Color> _corCache = {};

  Color? _corTopo;

  @override
  void initState() {
    super.initState();
    _carregarCor();
  }

  @override
  void didUpdateWidget(covariant _FundoDinamico oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.capaUrl != widget.capaUrl) {
      _corTopo = _corCache[widget.capaUrl];
      _carregarCor();
    }
  }

  Future<void> _carregarCor() async {
    final url = widget.capaUrl;
    if (url == null) {
      if (mounted) setState(() => _corTopo = null);
      return;
    }
    final cacheada = _corCache[url];
    if (cacheada != null) {
      if (mounted) setState(() => _corTopo = cacheada);
      return;
    }
    try {
      final colorScheme = await ColorScheme.fromImageProvider(
        provider: CachedNetworkImageProvider(url),
        brightness: Brightness.dark,
      );
      _corCache[url] = colorScheme.primary;
      // A faixa pode ter mudado de novo enquanto a extração rodava —
      // só aplica se ainda for a capa atual.
      if (mounted && widget.capaUrl == url) {
        setState(() => _corTopo = colorScheme.primary);
      }
    } catch (_) {
      // Sem sorte extraindo a cor (rede, imagem inválida etc) — mantém o
      // gradiente padrão, não é crítico pro player funcionar.
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (_corTopo ?? AppTheme.surfaceHigh).withOpacity(0.55),
            AppTheme.background,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: widget.child,
    );
  }
}
