import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/device_id_service.dart';
import '../core/theme.dart';
import '../services/player_service.dart';

/// Fila de reprodução atual — mostra as faixas em ordem e permite arrastar
/// pra reordenar (usa PlayerService.reordenarFila, que mexe direto na
/// ConcatenatingAudioSource sem parar a música).
class FilaScreen extends StatelessWidget {
  const FilaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fila')),
      body: Consumer<PlayerService>(
        builder: (context, player, _) {
          final fila = player.fila;

          if (fila.isEmpty) {
            return const Center(
              child: Text('Fila vazia.', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }

          return ReorderableListView.builder(
            itemCount: fila.length,
            onReorder: (oldIndex, newIndex) {
              player.reordenarFila(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final track = fila[index];
              final tocandoAgora = index == player.indiceAtual;
              final capaUrl = track.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);

              return ListTile(
                key: ValueKey('${track.id}_$index'),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        capaUrl != null
                            ? CachedNetworkImage(
                                imageUrl: capaUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 130,
                                placeholder: (context, url) =>
                                    Container(color: AppTheme.surfaceHigh),
                                errorWidget: (context, url, error) =>
                                    Container(color: AppTheme.surfaceHigh),
                              )
                            : Container(color: AppTheme.surfaceHigh),
                        if (tocandoAgora)
                          Container(
                            color: Colors.black54,
                            child: const Icon(Icons.volume_up, color: AppTheme.accent),
                          ),
                      ],
                    ),
                  ),
                ),
                title: Text(
                  track.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tocandoAgora ? AppTheme.accent : AppTheme.textPrimary,
                    fontWeight: tocandoAgora ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: track.albumNome.isNotEmpty
                    ? Text(
                        track.albumNome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      )
                    : null,
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle, color: AppTheme.textSecondary),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
