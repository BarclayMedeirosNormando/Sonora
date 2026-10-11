import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../services/device_id_service.dart';
import '../core/theme.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/historico_service.dart';
import '../services/library_cache_service.dart';
import '../services/player_service.dart';
import 'package:provider/provider.dart';
import 'folder_screen.dart';
import '../widgets/album_skeleton.dart';

/// Máximo de faixas mostradas na busca por música — sem essa trava, um
/// termo muito genérico (ex: uma letra só) numa biblioteca de centenas de
/// milhares de faixas listaria tudo de uma vez.
const _maxResultadosFaixas = 40;

/// Busca por nome de álbum/artista OU de faixa individual na biblioteca
/// inteira, usando o cache pré-computado (backend/CacheBiblioteca.gs) —
/// não faz nenhuma chamada ao Apps Script, então não pesa no backend nem
/// depende de navegar pasta por pasta pra achar algo.
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

  Future<void> _tocarFaixa(BuildContext context, Track faixa) async {
    final paiId = faixa.paiId;
    if (paiId == null) return;
    // Busca as faixas irmãs (mesmo álbum) pra montar uma fila de verdade
    // — igual à navegação normal por pasta — em vez de tocar só essa
    // faixa isolada, sem próxima/anterior fazendo sentido nenhum.
    final conteudo = await LibraryCacheService.obterConteudoDaPasta(paiId);
    final indice = conteudo.faixas.indexWhere((f) => f.id == faixa.id);
    if (indice == -1 || !context.mounted) return;
    context.read<PlayerService>().tocarFila(conteudo.faixas, indice);
    context.read<HistoricoService>().registrarFaixa(conteudo.faixas[indice]);
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
            hintText: 'Buscar artista, álbum ou música...',
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

          final albunsCorrespondentes = todos
              .where((a) => _normalizar(a.displayName).contains(termoNormalizado))
              .toList();

          final todasFaixas = LibraryCacheService.faixasSincronas ?? const <Track>[];
          final faixasCorrespondentes = todasFaixas
              .where((f) => _normalizar(f.displayTitle).contains(termoNormalizado))
              .take(_maxResultadosFaixas)
              .toList();

          if (albunsCorrespondentes.isEmpty && faixasCorrespondentes.isEmpty) {
            return const Center(
              child: Text(
                'Nada encontrado.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }

          return ListView(
            children: [
              if (albunsCorrespondentes.isNotEmpty) ...[
                const _TituloResultado('Álbuns'),
                for (final album in albunsCorrespondentes)
                  _ResultadoAlbumTile(album: album),
              ],
              if (faixasCorrespondentes.isNotEmpty) ...[
                const _TituloResultado('Músicas'),
                for (final faixa in faixasCorrespondentes)
                  _ResultadoFaixaTile(
                    faixa: faixa,
                    onTap: () => _tocarFaixa(context, faixa),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TituloResultado extends StatelessWidget {
  final String texto;

  const _TituloResultado(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ResultadoAlbumTile extends StatelessWidget {
  final Album album;

  const _ResultadoAlbumTile({required this.album});

  @override
  Widget build(BuildContext context) {
    final capaUrl = album.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);

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

class _ResultadoFaixaTile extends StatelessWidget {
  final Track faixa;
  final VoidCallback onTap;

  const _ResultadoFaixaTile({required this.faixa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final album = faixa.paiId != null ? LibraryCacheService.albumPorId(faixa.paiId!) : null;

    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.music_note, color: AppTheme.accent, size: 20),
      ),
      title: Text(
        faixa.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      subtitle: album != null
          ? Text(
              album.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )
          : null,
      onTap: onTap,
    );
  }
}
