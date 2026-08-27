import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/library_cache_service.dart';
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.surfaceHigh, AppTheme.background],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Consumer<PlayerService>(
        builder: (context, player, _) {
          final faixa = player.faixaAtual;
          if (faixa == null) {
            return const Center(
              child: Text(
                'Nada tocando',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Builder(
                  builder: (context) {
                    final album = faixa.paiId != null
                        ? LibraryCacheService.albumPorId(faixa.paiId!)
                        : null;
                    final capaUrl = album?.capaUrl(AppConstants.driveApiKey);
                    const placeholder = Center(
                      child: Icon(Icons.album, size: 96, color: AppTheme.textSecondary),
                    );

                    return Hero(
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
                    ));
                  },
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
                const SizedBox(height: 24),
                StreamBuilder<Duration>(
                  stream: player.posicaoStream,
                  builder: (context, snapshot) {
                    final posicao = snapshot.data ?? Duration.zero;
                    final duracao = player.duracao;
                    final totalMs =
                        duracao.inMilliseconds > 0 ? duracao.inMilliseconds.toDouble() : 1.0;
                    final atualMs =
                        posicao.inMilliseconds.clamp(0, totalMs.toInt()).toDouble();

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
          );
        },
        ),
      ),
    );
  }
}
