import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/historico_service.dart';
import '../services/player_service.dart';
import 'folder_screen.dart';

/// Tela de histórico: últimas pastas e faixas abertas/tocadas.
class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Limpar histórico',
            onPressed: () => context.read<HistoricoService>().limpar(),
          ),
        ],
      ),
      body: Consumer<HistoricoService>(
        builder: (context, historico, _) {
          final pastas = historico.pastas;
          final faixas = historico.faixas;

          if (pastas.isEmpty && faixas.isEmpty) {
            return const Center(
              child: Text(
                'Nada no histórico ainda.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return ListView(
            children: [
              if (pastas.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Pastas',
                    style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
                for (final pasta in pastas)
                  ListTile(
                    leading: const Icon(Icons.folder, color: AppTheme.accent),
                    title: Text(
                      pasta.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FolderScreen(folderId: pasta.id, title: pasta.name),
                        ),
                      );
                    },
                  ),
              ],
              if (faixas.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Faixas',
                    style: TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                  ),
                ),
                for (final track in faixas)
                  ListTile(
                    leading: const Icon(Icons.music_note, color: AppTheme.textSecondary),
                    title: Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                    onTap: () => context.read<PlayerService>().tocarFila([track], 0),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
