import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/device_id_service.dart';
import '../services/player_service.dart';

/// Mostra as faixas de uma playlist curada e toca pelo PlayerService de
/// sempre -- as faixas vêm prontas do backend (nome/álbum/capa já
/// resolvidos na curadoria), então são convertidas pra Track só pra
/// reaproveitar tocarFila()/streamUrl() sem duplicar lógica de player.
class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String nome;

  const PlaylistScreen({super.key, required this.playlistId, required this.nome});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<Playlist> _playlistFuture;

  @override
  void initState() {
    super.initState();
    _playlistFuture = _carregar();
  }

  Future<Playlist> _carregar() async {
    final appId = await DeviceIdService.getOrCreateDeviceId();
    return ApiService.obterPlaylist(widget.playlistId, appId);
  }

  Future<void> _recarregar() async {
    setState(() {
      _playlistFuture = _carregar();
    });
    await _playlistFuture;
  }

  /// Converte as faixas curadas (PlaylistFaixa) pra Track -- o formato
  /// que PlayerService.tocarFila espera. O fileId da faixa curada é o
  /// mesmo ID de arquivo do Drive que Track.id usa pra montar a URL de
  /// streaming (Track.streamUrl), então essa conversão é direta.
  List<Track> _comoFaixas(Playlist playlist) {
    return playlist.faixas
        .map((f) => Track(id: f.fileId, title: f.nome, paiId: f.albumId))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.nome)),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<Playlist>(
          future: _playlistFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 60, 24, 0),
                    child: Center(
                      child: Text(
                        'Não foi possível carregar essa playlist.\nPuxe pra baixo pra tentar de novo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }

            final playlist = snapshot.data!;
            if (playlist.faixas.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 60, 24, 0),
                    child: Center(
                      child: Text(
                        'Essa playlist ainda não tem faixas.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  ),
                ],
              );
            }

            final faixasParaTocar = _comoFaixas(playlist);

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: playlist.faixas.length,
              itemBuilder: (context, index) {
                final faixa = playlist.faixas[index];
                return _FaixaPlaylistTile(
                  faixa: faixa,
                  onTap: () {
                    context.read<PlayerService>().tocarFila(faixasParaTocar, index);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FaixaPlaylistTile extends StatelessWidget {
  final PlaylistFaixa faixa;
  final VoidCallback onTap;

  const _FaixaPlaylistTile({required this.faixa, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final capaUrl = faixa.capaUrl(AppConstants.driveApiKey);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 44,
          child: capaUrl != null
              ? CachedNetworkImage(
                  imageUrl: capaUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 130,
                  placeholder: (context, url) => Container(color: AppTheme.surfaceHigh),
                  errorWidget: (context, url, error) =>
                      Container(color: AppTheme.surfaceHigh),
                )
              : Container(
                  color: AppTheme.surfaceHigh,
                  child: const Icon(Icons.music_note, color: AppTheme.accent, size: 20),
                ),
        ),
      ),
      title: Text(
        faixa.displayNome,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.textPrimary),
      ),
      subtitle: faixa.albumNome.isNotEmpty
          ? Text(
              faixa.albumNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            )
          : null,
      onTap: onTap,
    );
  }
}
