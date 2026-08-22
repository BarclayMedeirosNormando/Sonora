import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/album.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';

/// Lista as faixas (MP3s) de um álbum.
class AlbumScreen extends StatefulWidget {
  final Album album;

  const AlbumScreen({super.key, required this.album});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  late Future<List<Track>> _faixasFuture;

  @override
  void initState() {
    super.initState();
    _faixasFuture = ApiService.listarFaixas(widget.album.id);
  }

  Future<void> _recarregar() async {
    setState(() {
      _faixasFuture = ApiService.listarFaixas(widget.album.id);
    });
    await _faixasFuture;
  }

  void _tocar(List<Track> faixas, int indice) {
    context.read<PlayerService>().tocarFila(faixas, indice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.displayName)),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _recarregar,
              child: FutureBuilder<List<Track>>(
                future: _faixasFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return _mensagem(
                        'Não deu pra carregar as faixas.\n${snapshot.error}');
                  }

                  final faixas = snapshot.data ?? [];
                  if (faixas.isEmpty) {
                    return _mensagem('Nenhuma faixa MP3 encontrada nesse álbum.');
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: faixas.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      color: AppTheme.surfaceHigh,
                    ),
                    itemBuilder: (context, index) => _TrackTile(
                      track: faixas[index],
                      numero: index + 1,
                      onTap: () => _tocar(faixas, index),
                    ),
                  );
                },
              ),
            ),
          ),
          const MiniPlayer(),
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

class _TrackTile extends StatelessWidget {
  final Track track;
  final int numero;
  final VoidCallback onTap;

  const _TrackTile({
    required this.track,
    required this.numero,
    required this.onTap,
  });

  String get _tamanhoFormatado {
    final mb = track.sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SizedBox(
        width: 28,
        child: Text(
          '$numero',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
      title: Text(
        track.displayTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      trailing: Text(
        _tamanhoFormatado,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}
