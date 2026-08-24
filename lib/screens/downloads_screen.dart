import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/download_service.dart';
import '../services/historico_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';

/// Faixas já baixadas no aparelho — a única tela do app que funciona sem
/// internet nenhuma, porque não depende do cache da biblioteca (que
/// precisa buscar no Drive) nem do backend: só lê o que já foi salvo
/// localmente pelo DownloadService.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final baixadas = context.watch<DownloadService>().todasBaixadas;

    return Scaffold(
      appBar: AppBar(title: const Text('Baixadas (offline)')),
      body: Column(
        children: [
          Expanded(
            child: baixadas.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma faixa baixada ainda.\n'
                        'Toque no ícone de download ao lado de uma faixa '
                        'pra poder ouvir ela sem internet depois.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: baixadas.length,
                    itemBuilder: (context, index) {
                      final item = baixadas[index];
                      return ListTile(
                        leading: const Icon(Icons.download_done, color: AppTheme.accent),
                        title: Text(
                          item.track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary),
                          tooltip: 'Remover download',
                          onPressed: () =>
                              context.read<DownloadService>().remover(item.track.id),
                        ),
                        onTap: () {
                          final faixas = baixadas.map((b) => b.track).toList();
                          context.read<PlayerService>().tocarFila(faixas, index);
                          context.read<HistoricoService>().registrarFaixa(item.track);
                        },
                      );
                    },
                  ),
          ),
          const MiniPlayer(),
        ],
      ),
    );
  }
}
