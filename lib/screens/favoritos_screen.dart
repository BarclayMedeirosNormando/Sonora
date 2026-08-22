import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/favoritos_service.dart';
import 'folder_screen.dart';

/// Lista as pastas marcadas como favoritas (com a estrela no card).
class FavoritosScreen extends StatelessWidget {
  const FavoritosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: Consumer<FavoritosService>(
        builder: (context, favoritosService, _) {
          final lista = favoritosService.favoritos;

          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum favorito ainda.\nToque na estrela de uma pasta pra adicionar aqui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final item = lista[index];
              return ListTile(
                leading: const Icon(Icons.folder, color: AppTheme.accent),
                title: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => favoritosService.remover(item.id),
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FolderScreen(folderId: item.id, title: item.name),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
