import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/album.dart';
import '../services/favoritos_service.dart';
import '../services/historico_service.dart';
import '../services/library_cache_service.dart';
import '../services/player_service.dart';
import '../widgets/album_skeleton.dart';
import 'folder_screen.dart';
import 'pedido_screen.dart';
import 'player_screen.dart';

/// Tela inicial do app: continuar ouvindo, adicionados recentemente e
/// favoritos, tudo num só lugar — em vez de cair direto na lista crua de
/// pastas da biblioteca (que continua acessível pelo botão "Ver tudo").
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Album>> _recentesFuture;

  @override
  void initState() {
    super.initState();
    _recentesFuture = LibraryCacheService.obterAlbuns();
  }

  Future<void> _recarregar() async {
    setState(() {
      _recentesFuture = LibraryCacheService.obterAlbuns(forcarRecarga: true);
    });
    await _recentesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sonora'),
      ),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const _ContinuarOuvindo(),
            _SecaoAlbuns(
              titulo: 'Adicionados recentemente',
              future: _recentesFuture,
            ),
            const _SecaoFavoritos(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.chat_outlined, color: AppTheme.accent),
                label: const Text(
                  'Pedir música ou álbum',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PedidoScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;

  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ContinuarOuvindo extends StatelessWidget {
  const _ContinuarOuvindo();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final faixa = player.faixaAtual;
    if (faixa == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PlayerScreen()),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note, color: AppTheme.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Continuar ouvindo',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      faixa.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ),
              Icon(
                player.tocando ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: AppTheme.accent,
                size: 32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecaoAlbuns extends StatelessWidget {
  final String titulo;
  final Future<List<Album>> future;
  static const _maxItens = 12;

  const _SecaoAlbuns({required this.titulo, required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Album>>(
      future: future,
      builder: (context, snapshot) {
        final albuns = (snapshot.data ?? []).take(_maxItens).toList();
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TituloSecao(titulo),
              const AlbumRowSkeleton(quantidade: 5),
            ],
          );
        }

        if (albuns.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TituloSecao(titulo),
            SizedBox(
              height: 168,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: albuns.length,
                itemBuilder: (context, index) => _AlbumCardPequeno(album: albuns[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SecaoFavoritos extends StatelessWidget {
  const _SecaoFavoritos();

  @override
  Widget build(BuildContext context) {
    final favoritos = context.watch<FavoritosService>().favoritos;
    if (favoritos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TituloSecao('Favoritos'),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: favoritos.length,
            itemBuilder: (context, index) {
              final item = favoritos[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  backgroundColor: AppTheme.surface,
                  label: Text(
                    item.name,
                    style: const TextStyle(color: AppTheme.textPrimary),
                  ),
                  onPressed: () {
                    context.read<HistoricoService>().registrarPasta(item.id, item.name);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FolderScreen(folderId: item.id, title: item.name),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AlbumCardPequeno extends StatelessWidget {
  final Album album;

  const _AlbumCardPequeno({required this.album});

  @override
  Widget build(BuildContext context) {
    final capaUrl = album.capaUrl(AppConstants.driveApiKey);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 110,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            context.read<HistoricoService>().registrarPasta(album.id, album.displayName);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FolderScreen(folderId: album.id, title: album.displayName),
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: capaUrl != null
                      ? Image.network(
                          capaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const _CapaPequenaPlaceholder(),
                        )
                      : const _CapaPequenaPlaceholder(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                album.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapaPequenaPlaceholder extends StatelessWidget {
  const _CapaPequenaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceHigh,
      child: const Center(
        child: Icon(Icons.folder, color: AppTheme.accent, size: 24),
      ),
    );
  }
}
