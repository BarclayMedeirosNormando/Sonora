import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/device_id_service.dart';
import '../core/theme.dart';
import '../screens/player_screen.dart';
import '../services/player_service.dart';
import 'capa_placeholder.dart';

/// Mini-player flutuante (cartão arredondado com sombra) que fica acima do
/// fim da tela em todo o app. Tem uma barrinha fina de progresso no topo e
/// a miniatura da capa (com Hero animation pra tela cheia do player).
/// Some sozinho quando não há nada tocando.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerService>(
      builder: (context, player, _) {
        final faixa = player.faixaAtual;
        if (faixa == null) return const SizedBox.shrink();

        final capaUrl = faixa.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);
        const capaPadrao = CapaPlaceholder(semente: 'sonora', tamanhoIcone: 18);

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PlayerScreen()),
                  );
                },
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
                      height: 60,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'capa-${faixa.id}',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 42,
                                  height: 42,
                                  child: capaUrl != null
                                      ? CachedNetworkImage(
                                          imageUrl: capaUrl,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 90,
                                          placeholder: (context, url) => capaPadrao,
                                          errorWidget: (context, url, error) => capaPadrao,
                                        )
                                      : capaPadrao,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    faixa.displayTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (faixa.albumNome.isNotEmpty)
                                    Text(
                                      faixa.albumNome,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                player.tocando
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: AppTheme.textPrimary,
                                size: 30,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                player.alternarPlayPause();
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: AppTheme.textPrimary,
                                size: 28,
                              ),
                              onPressed: player.proxima,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
