import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

              return ListTile(
                key: ValueKey('${track.id}_$index'),
                leading: Icon(
                  tocandoAgora ? Icons.volume_up : Icons.music_note,
                  color: tocandoAgora ? AppTheme.accent : AppTheme.textSecondary,
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
