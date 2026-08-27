import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/album.dart';
import '../models/pasta_conteudo.dart';
import '../models/track.dart';
import '../services/download_service.dart';
import '../services/favoritos_service.dart';
import '../services/historico_service.dart';
import '../services/library_cache_service.dart';
import '../services/player_service.dart';
import '../widgets/album_skeleton.dart';
import '../widgets/mini_player.dart';
import 'downloads_screen.dart';
import 'favoritos_screen.dart';
import 'historico_screen.dart';

/// Navegador genérico de pastas do Drive: mostra subpastas e faixas MP3
/// que estão dentro da pasta atual, como um explorador de arquivos.
/// Funciona em qualquer profundidade — cada subpasta abre uma nova
/// FolderScreen, sem precisar saber de antemão quantos níveis existem.
class FolderScreen extends StatefulWidget {
  final String folderId;
  final String title;
  /// false quando essa tela é o conteúdo de uma aba (a casca com abas já
  /// mostra o mini-player por cima da barra) — true (padrão) quando é uma
  /// tela cheia normal, empilhada por cima de tudo via Navigator.push.
  final bool mostrarMiniPlayer;

  const FolderScreen({
    super.key,
    required this.folderId,
    required this.title,
    this.mostrarMiniPlayer = true,
  });

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  late Future<PastaConteudo> _conteudoFuture;

  @override
  void initState() {
    super.initState();
    _conteudoFuture = LibraryCacheService.obterConteudoDaPasta(widget.folderId);
  }

  Future<void> _recarregar() async {
    setState(() {
      _conteudoFuture = LibraryCacheService.obterConteudoDaPasta(
        widget.folderId,
        forcarRecarga: true,
      );
    });
    await _conteudoFuture;
  }

  void _tocar(List<Track> faixas, int indice) {
    context.read<PlayerService>().tocarFila(faixas, indice);
    context.read<HistoricoService>().registrarFaixa(faixas[indice]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Histórico',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoricoScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.star),
            tooltip: 'Favoritos',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FavoritosScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.download_done),
            tooltip: 'Baixadas (offline)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _recarregar,
              child: FutureBuilder<PastaConteudo>(
                future: _conteudoFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AlbumGridSkeleton();
                  }

                  if (snapshot.hasError) {
                    return _mensagem(
                        'Não deu pra carregar essa pasta.\n${snapshot.error}');
                  }

                  final conteudo = snapshot.data;
                  final pastas = conteudo?.pastas ?? [];
                  final faixas = conteudo?.faixas ?? [];

                  if (pastas.isEmpty && faixas.isEmpty) {
                    return _mensagem('Pasta vazia.');
                  }

                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (pastas.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.62,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) =>
                                  _PastaCard(pasta: pastas[index]),
                              childCount: pastas.length,
                            ),
                          ),
                        ),
                      if (pastas.isNotEmpty && faixas.isNotEmpty)
                        const SliverToBoxAdapter(
                          child: Divider(height: 1, color: AppTheme.surfaceHigh),
                        ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _TrackTile(
                            track: faixas[index],
                            onTap: () => _tocar(faixas, index),
                          ),
                          childCount: faixas.length,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (widget.mostrarMiniPlayer) const MiniPlayer(),
        ],
      ),
    );
  }

  Widget _mensagem(String texto) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                texto,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PastaCard extends StatelessWidget {
  final Album pasta;

  const _PastaCard({required this.pasta});

  @override
  Widget build(BuildContext context) {
    final capaUrl = pasta.capaUrl(AppConstants.driveApiKey);
    final ehFavorito = context.watch<FavoritosService>().ehFavorito(pasta.id);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        context.read<HistoricoService>().registrarPasta(pasta.id, pasta.displayName);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FolderScreen(folderId: pasta.id, title: pasta.displayName),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: capaUrl != null
                      ? Image.network(
                          capaUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const _CapaPlaceholder();
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              const _CapaPlaceholder(),
                        )
                      : const _CapaPlaceholder(),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => context
                        .read<FavoritosService>()
                        .alternar(pasta.id, pasta.displayName),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        ehFavorito ? Icons.star : Icons.star_border,
                        color: ehFavorito ? AppTheme.accent : Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              pasta.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CapaPlaceholder extends StatelessWidget {
  const _CapaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceHigh,
      child: const Center(
        child: Icon(Icons.folder, color: AppTheme.accent, size: 32),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;

  const _TrackTile({required this.track, required this.onTap});

  String get _tamanhoFormatado {
    final mb = track.sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();
    final status = downloadService.statusDe(track.id);

    return ListTile(
      leading: const Icon(Icons.music_note, color: AppTheme.textSecondary),
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _tamanhoFormatado,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          _BotaoDownload(
            track: track,
            status: status,
            progresso: downloadService.progressoDe(track.id),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play, color: AppTheme.textSecondary),
            tooltip: 'Tocar a seguir',
            onPressed: () {
              context.read<PlayerService>().tocarASeguir(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('"${track.displayTitle}" vai tocar a seguir')),
              );
            },
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Botão de baixar/remover uma faixa pra ouvir offline. Mostra o estado
/// certo conforme o download: nada baixado ainda, baixando (com
/// progresso), já baixada (toque remove), ou erro (toque tenta de novo).
class _BotaoDownload extends StatelessWidget {
  final Track track;
  final StatusDownload status;
  final double? progresso;

  const _BotaoDownload({required this.track, required this.status, this.progresso});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case StatusDownload.baixado:
        return IconButton(
          icon: const Icon(Icons.download_done, color: AppTheme.accent),
          tooltip: 'Baixada — toque pra remover',
          onPressed: () => context.read<DownloadService>().remover(track.id),
        );
      case StatusDownload.baixando:
        final valor = (progresso != null && progresso! > 0) ? progresso : null;
        return SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, value: valor),
            ),
          ),
        );
      case StatusDownload.erro:
        return IconButton(
          icon: const Icon(Icons.error_outline, color: Colors.redAccent),
          tooltip: 'Erro ao baixar — toque pra tentar de novo',
          onPressed: () => context.read<DownloadService>().baixar(track),
        );
      case StatusDownload.nenhum:
        return IconButton(
          icon: const Icon(Icons.download_outlined, color: AppTheme.textSecondary),
          tooltip: 'Baixar pra ouvir offline',
          onPressed: () => context.read<DownloadService>().baixar(track),
        );
    }
  }
}
