import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/album.dart';
import '../services/historico_service.dart';
import '../services/library_cache_service.dart';
import '../widgets/album_skeleton.dart';
import 'package:provider/provider.dart';
import 'folder_screen.dart';

/// Busca por nome de álbum/artista na biblioteca inteira, usando o cache
/// pré-computado (backend/CacheBiblioteca.gs) — não faz nenhuma chamada ao
/// Apps Script, então não pesa no backend nem depende de navegar pasta por
/// pasta pra achar algo.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  late Future<List<Album>> _todosFuture;
  String _termo = '';

  @override
  void initState() {
    super.initState();
    _todosFuture = LibraryCacheService.obterAlbuns();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _recarregar() {
    setState(() {
      _todosFuture = LibraryCacheService.obterAlbuns(forcarRecarga: true);
    });
  }

  /// Normaliza pra busca sem se importar com acento/maiúscula
  /// ("robeRTO" e "roberto" e "róbèrto" batem igual).
  String _normalizar(String texto) {
    const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
    const semAcento = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
    var resultado = texto.toLowerCase();
    for (var i = 0; i < comAcento.length; i++) {
      resultado = resultado.replaceAll(comAcento[i], semAcento[i].toLowerCase());
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Buscar artista ou álbum...',
            hintStyle: TextStyle(color: AppTheme.textSecondary),
            border: InputBorder.none,
          ),
          onChanged: (valor) => setState(() => _termo = valor),
        ),
      ),
      body: FutureBuilder<List<Album>>(
        future: _todosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlbumListSkeleton();
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não deu pra carregar a busca.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _recarregar,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
            );
          }

          final todos = snapshot.data ?? [];
          if (todos.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Busca ainda não configurada.\nRode o gerador de cache da biblioteca.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }

          if (_termo.trim().isEmpty) {
            return const Center(
              child: Text(
                'Digite pra buscar',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          final termoNormalizado = _normalizar(_termo.trim());
          final resultados = todos
              .where((a) => _normalizar(a.displayName).contains(termoNormalizado))
              .toList();

          if (resultados.isEmpty) {
            return const Center(
              child: Text(
                'Nada encontrado.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return ListView.builder(
            itemCount: resultados.length,
            itemBuilder: (context, index) => _ResultadoTile(album: resultados[index]),
          );
        },
      ),
    );
  }
}

class _ResultadoTile extends StatelessWidget {
  final Album album;

  const _ResultadoTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final capaUrl = album.capaUrl(AppConstants.driveApiKey);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: capaUrl != null
              ? CachedNetworkImage(
                  imageUrl: capaUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  placeholder: (context, url) => Container(
                    color: AppTheme.surfaceHigh,
                    child: const Icon(Icons.folder, color: AppTheme.accent, size: 20),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: AppTheme.surfaceHigh,
                    child: const Icon(Icons.folder, color: AppTheme.accent, size: 20),
                  ),
                )
              : Container(
                  color: AppTheme.surfaceHigh,
                  child: const Icon(Icons.folder, color: AppTheme.accent, size: 20),
                ),
        ),
      ),
      title: Text(
        album.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      onTap: () {
        context.read<HistoricoService>().registrarPasta(album.id, album.displayName);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FolderScreen(folderId: album.id, title: album.displayName),
          ),
        );
      },
    );
  }
}
