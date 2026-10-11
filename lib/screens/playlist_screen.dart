import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/device_id_service.dart';
import '../services/download_service.dart';
import '../services/offline_playlist_service.dart';
import '../services/player_service.dart';
import '../services/playlist_vistas_service.dart';
import '../widgets/capa_placeholder.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/mini_player.dart';
import '../widgets/skeletons.dart';

/// Mostra as faixas de uma playlist curada e toca pelo PlayerService de
/// sempre -- as faixas vêm prontas do backend (nome/álbum/capa já
/// resolvidos na curadoria), então são convertidas pra Track só pra
/// reaproveitar tocarFila()/streamUrl() sem duplicar lógica de player.
///
/// Tem o cabeçalho com capa + botões Tocar/Aleatório e o botão de modo
/// offline (AppBar): baixa todas as faixas da playlist e mantém em dia as
/// que entrarem depois (ver OfflinePlaylistService).
class PlaylistScreen extends StatefulWidget {
  final String playlistId;
  final String nome;

  const PlaylistScreen({super.key, required this.playlistId, required this.nome});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<Playlist> _playlistFuture;

  /// Última playlist carregada -- o botão de offline da AppBar precisa
  /// dela (a AppBar fica fora do FutureBuilder).
  Playlist? _playlist;

  /// fileIds das faixas que entraram desde a última vez que o usuário
  /// abriu essa playlist -- ganham selo "NOVA" e o aviso no topo.
  Set<String> _novas = {};

  @override
  void initState() {
    super.initState();
    _playlistFuture = _carregar();
  }

  Future<Playlist> _carregar() async {
    // Lido antes do primeiro await, enquanto o context ainda é seguro.
    final offline = context.read<OfflinePlaylistService>();
    final appId = await DeviceIdService.getOrCreateDeviceId();
    final playlist = await ApiService.obterPlaylist(widget.playlistId, appId);
    // Descobre o que é novo e já marca tudo como visto. Acumula em _novas
    // pra o destaque não sumir se o usuário puxar pra atualizar.
    final novas = await PlaylistVistasService.marcarVista(playlist);
    _novas = {..._novas, ...novas};
    // Se o modo offline dessa playlist estiver ligado, já baixa o que
    // entrou de novo (e apaga o que saiu).
    await offline.sincronizar(playlist);
    if (mounted) setState(() => _playlist = playlist);
    return playlist;
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
        .map(
          (f) => Track(
            id: f.fileId,
            title: f.nome,
            paiId: f.albumId,
            capaId: f.capaId,
            albumNome: f.albumNome,
          ),
        )
        .toList();
  }

  /// Toca a playlist a partir de [indice] -- ou, com [aleatorio], começa
  /// numa faixa sorteada e liga o modo aleatório. Sem internet, a fila só
  /// pode ter faixas já baixadas, senão o player trava tentando fazer
  /// streaming das outras.
  Future<void> _tocar(
    List<Track> faixas,
    int indice,
    OfflinePlaylistService offline,
    DownloadService downloads, {
    bool aleatorio = false,
  }) async {
    final player = context.read<PlayerService>();
    final mensagens = ScaffoldMessenger.of(context);

    var fila = faixas;
    var inicio = indice;
    if (!offline.temRede) {
      fila = faixas
          .where((t) => downloads.statusDe(t.id) == StatusDownload.baixado)
          .toList();
      inicio = aleatorio
          ? (fila.isEmpty ? -1 : 0)
          : fila.indexWhere((t) => t.id == faixas[indice].id);
      if (inicio < 0) {
        mensagens.showSnackBar(
          const SnackBar(
            content: Text('Sem internet: essa música não foi baixada.'),
          ),
        );
        return;
      }
    }

    if (aleatorio) inicio = math.Random().nextInt(fila.length);

    HapticFeedback.selectionClick();
    await player.tocarFila(fila, inicio);
    if (aleatorio && !player.modoAleatorio) await player.alternarAleatorio();
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflinePlaylistService>();
    final downloads = context.watch<DownloadService>();
    final carregada = _playlist;

    return Scaffold(
      // A tela da playlist cobre a casca principal, então precisa do próprio
      // mini-player pra dar pra controlar o que está tocando daqui.
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      appBar: AppBar(
        // Depois de carregada, o nome aparece grande no cabeçalho da lista.
        title: carregada == null ? Text(widget.nome) : null,
        actions: [
          if (carregada != null) _BotaoOffline(playlist: carregada),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: _recarregar,
        child: FutureBuilder<Playlist>(
          future: _playlistFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SkeletonFaixas()],
              );
            }

            if (snapshot.hasError && !snapshot.hasData) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  EstadoVazio(
                    icone: Icons.wifi_off_rounded,
                    titulo: 'Não foi possível carregar',
                    mensagem: 'Puxe pra baixo pra tentar de novo.',
                    rotuloAcao: 'Tentar de novo',
                    aoAcionar: _recarregar,
                  ),
                ],
              );
            }

            final playlist = snapshot.data!;
            if (playlist.faixas.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  EstadoVazio(
                    icone: Icons.library_music_outlined,
                    titulo: 'Playlist vazia',
                    mensagem: 'Essa playlist ainda não tem faixas.',
                  ),
                ],
              );
            }

            final faixasParaTocar = _comoFaixas(playlist);
            final cabecalhos = <Widget>[
              _CabecalhoPlaylist(
                playlist: playlist,
                onTocar: () => _tocar(faixasParaTocar, 0, offline, downloads),
                onAleatorio: () =>
                    _tocar(faixasParaTocar, 0, offline, downloads, aleatorio: true),
              ),
              if (offline.estaAtiva(playlist.id)) _StatusOffline(playlistId: playlist.id),
              if (_novas.isNotEmpty) _AvisoNovas(quantidade: _novas.length),
            ];

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: playlist.faixas.length + cabecalhos.length,
              itemBuilder: (context, i) {
                if (i < cabecalhos.length) return cabecalhos[i];
                final index = i - cabecalhos.length;
                final faixa = playlist.faixas[index];
                final baixada =
                    downloads.statusDe(faixa.fileId) == StatusDownload.baixado;
                return _FaixaPlaylistTile(
                  faixa: faixa,
                  nova: _novas.contains(faixa.fileId),
                  baixada: baixada,
                  // Sem internet, o que não foi baixado fica apagado.
                  indisponivel: !offline.temRede && !baixada,
                  onTap: () => _tocar(faixasParaTocar, index, offline, downloads),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Topo da playlist: capa grande, nome, quantidade e os botões
/// Tocar / Aleatório.
class _CabecalhoPlaylist extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTocar;
  final VoidCallback onAleatorio;

  const _CabecalhoPlaylist({
    required this.playlist,
    required this.onTocar,
    required this.onAleatorio,
  });

  @override
  Widget build(BuildContext context) {
    final capaUrl = playlist.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);
    final capaPadrao = CapaPlaceholder(semente: playlist.nome, tamanhoIcone: 56);
    final total = playlist.faixas.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: capaUrl != null
                  ? CachedNetworkImage(
                      imageUrl: capaUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 400,
                      placeholder: (context, url) => capaPadrao,
                      errorWidget: (context, url, error) => capaPadrao,
                    )
                  : capaPadrao,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            playlist.nome,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$total música${total == 1 ? '' : 's'}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onTocar,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Tocar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAleatorio,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Aleatório'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.surfaceHigh, width: 1.5),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botão da AppBar: liga/desliga o modo offline da playlist.
class _BotaoOffline extends StatelessWidget {
  final Playlist playlist;

  const _BotaoOffline({required this.playlist});

  Future<void> _alternar(BuildContext context) async {
    final offline = context.read<OfflinePlaylistService>();
    final mensagens = ScaffoldMessenger.of(context);
    HapticFeedback.selectionClick();

    if (!offline.estaAtiva(playlist.id)) {
      await offline.ativar(playlist);
      mensagens.showSnackBar(
        SnackBar(
          content: Text(
            offline.temWifi
                ? 'Baixando a playlist pra ouvir offline...'
                : 'Modo offline ligado. O download começa quando o aparelho estiver no Wi-Fi.',
          ),
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desligar o modo offline?'),
        content: const Text(
          'As músicas baixadas dessa playlist serão apagadas do aparelho e as novas não serão mais baixadas sozinhas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desligar'),
          ),
        ],
      ),
    );
    if (confirmar == true) await offline.desativar(playlist.id);
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflinePlaylistService>();
    // Só pra reconstruir conforme as faixas terminam de baixar.
    context.watch<DownloadService>();
    final ativa = offline.estaAtiva(playlist.id);
    final completa = offline.completa(playlist.id);

    return IconButton(
      tooltip: ativa ? 'Modo offline ligado' : 'Baixar pra ouvir offline',
      icon: Icon(
        ativa
            ? (completa ? Icons.offline_pin : Icons.downloading)
            : Icons.download_for_offline_outlined,
        color: ativa ? AppTheme.accent : null,
      ),
      onPressed: () => _alternar(context),
    );
  }
}

/// Faixa de status no topo da playlist quando o modo offline está ligado.
class _StatusOffline extends StatelessWidget {
  final String playlistId;

  const _StatusOffline({required this.playlistId});

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<OfflinePlaylistService>();
    context.watch<DownloadService>();
    final total = offline.totalDe(playlistId);
    final baixadas = offline.baixadasDe(playlistId);
    final completa = total > 0 && baixadas >= total;

    final String texto;
    if (completa) {
      texto = 'Disponível offline ($total músicas)';
    } else if (offline.temWifi) {
      texto = 'Baixando pra ouvir offline: $baixadas de $total';
    } else {
      texto = '$baixadas de $total baixadas. O resto baixa quando estiver no Wi-Fi.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completa ? Icons.offline_pin : Icons.downloading,
                color: AppTheme.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  texto,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
          if (!completa && total > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: baixadas / total,
                minHeight: 4,
                backgroundColor: AppTheme.surfaceHigh,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FaixaPlaylistTile extends StatelessWidget {
  final PlaylistFaixa faixa;
  final bool nova;
  final bool baixada;
  final bool indisponivel;
  final VoidCallback onTap;

  const _FaixaPlaylistTile({
    required this.faixa,
    required this.onTap,
    this.nova = false,
    this.baixada = false,
    this.indisponivel = false,
  });

  @override
  Widget build(BuildContext context) {
    final capaUrl = faixa.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);

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
        style: TextStyle(
          color: indisponivel
              ? AppTheme.textPrimary.withValues(alpha: 0.4)
              : AppTheme.textPrimary,
        ),
      ),
      subtitle: faixa.albumNome.isNotEmpty
          ? Text(
              faixa.albumNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: indisponivel
                    ? AppTheme.textSecondary.withValues(alpha: 0.4)
                    : AppTheme.textSecondary,
                fontSize: 12,
              ),
            )
          : null,
      trailing: (nova || baixada)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (nova) const _SeloNova(),
                if (nova && baixada) const SizedBox(width: 8),
                if (baixada)
                  const Icon(Icons.download_done, size: 18, color: AppTheme.accent),
              ],
            )
          : null,
      onTap: onTap,
    );
  }
}

/// Faixa que entrou na playlist desde a última visita.
class _SeloNova extends StatelessWidget {
  const _SeloNova();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'NOVA',
        style: TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Faixa de aviso no topo da playlist quando entrou música nova.
class _AvisoNovas extends StatelessWidget {
  final int quantidade;

  const _AvisoNovas({required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final plural = quantidade == 1 ? '' : 's';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_new, color: AppTheme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$quantidade música$plural nova$plural nessa playlist',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
