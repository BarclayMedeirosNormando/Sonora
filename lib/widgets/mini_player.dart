import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../screens/player_screen.dart';
import '../services/player_service.dart';

/// Barra fixa na parte inferior das telas com a faixa atual e play/pause.
/// Tem uma barrinha fina de progresso no topo, igual Spotify/Apple Music.
/// Some sozinha quando não há nada tocando.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerService>(
      builder: (context, player, _) {
        final faixa = player.faixaAtual;
        if (faixa == null) return const SizedBox.shrink();

        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          },
          child: Container(
            color: AppTheme.surfaceHigh,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration>(
                  stream: player.posicaoStream,
                  builder: (context, snapshot) {
                    final posicao = snapshot.data ?? Duration.zero;
                    final duracao = player.duracao;
                    final progresso = duracao.inMilliseconds > 0
                        ? (posicao.inMilliseconds / duracao.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: progresso,
                      minHeight: 2,
                      backgroundColor: Colors.black26,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                    );
                  },
                ),
                SizedBox(
                  height: 62,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note, color: AppTheme.textSecondary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            faixa.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            player.tocando ? Icons.pause : Icons.play_arrow,
                            color: AppTheme.textPrimary,
                          ),
                          onPressed: player.alternarPlayPause,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
