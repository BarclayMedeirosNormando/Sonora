import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';
import '../services/device_id_service.dart';
import '../services/player_service.dart';
import '../services/playlist_vistas_service.dart';
import 'player_screen.dart';
import 'playlist_screen.dart';

/// Tela inicial do app: lista as playlists curadas direcionadas a este
/// App_ID (ver GET /api/playlists no backend) -- a navegação livre pelas
/// pastas cruas do Drive saiu daqui; o usuário só vê o que foi
/// selecionado especificamente pra ele na curadoria (17/09/2026).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeDados> _playlistsFuture;
  String? _appId;

  @override
  void initState() {
    super.initState();
    _playlistsFuture = _carregarPlaylists();
    // Carregado separado da lista de playlists -- o App_ID já está em
    // cache local (DeviceIdService), então isso resolve quase instantâneo
    // e não precisa bloquear o resto da tela.
    DeviceIdService.getOrCreateDeviceId().then((id) {
      if (mounted) setState(() => _appId = id);
    });
  }

  Future<_HomeDados> _carregarPlaylists() async {
    final appId = await DeviceIdService.getOrCreateDeviceId();
    final playlists = await ApiService.obterPlaylists(appId);
    final novidades = await PlaylistVistasService.verificar(playlists);
    return _HomeDados(playlists, novidades);
  }

  /// Ao voltar de uma playlist, reavalia só as novidades (o selo some
  /// depois que o usuário abriu) sem refazer a chamada de rede.
  Future<void> _aoVoltarDaPlaylist() async {
    final dados = await _playlistsFuture;
    final novidades = await PlaylistVistasService.verificar(dados.playlists);
    if (!mounted) return;
    setState(() {
      _playlistsFuture = Future.value(_HomeDados(dados.playlists, novidades));
    });
  }

  Future<void> _recarregar() async {
    setState(() {
      _playlistsFuture = _carregarPlaylists();
    });
    await _playlistsFuture;
  }

  void _copiarAppId() {
    final id = _appId;
    if (id == null) return;
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('ID $id copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Sonora'),
            const SizedBox(width: 6),
            Text(
              'v${AppConstants.appVersionLabel}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: AppTheme.textSecondary.withOpacity(0.75),
              ),
            ),
          ],
        ),
        // ID do dispositivo, sempre visível -- pra pessoa conseguir
        // mandar de novo (ex: pra liberar/direcionar outra playlist) sem
        // precisar desinstalar e reinstalar pra ver de novo a tela de
        // validação. Toque copia pro clipboard.
        actions: [
          if (_appId != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: _copiarAppId,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ID: $_appId',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 14, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const _ContinuarOuvindo(),
            _SecaoPlaylists(future: _playlistsFuture, onVoltar: _aoVoltarDaPlaylist),
          ],
        ),
      ),
    );
  }
}

/// Resultado do carregamento da Home: as playlists + o que tem de novo.
class _HomeDados {
  final List<PlaylistResumo> playlists;
  final Map<String, NovidadePlaylist> novidades;

  const _HomeDados(this.playlists, this.novidades);
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

/// Lista as playlists curadas pra este App_ID -- cards grandes,
/// verticais (diferente da fileira horizontal de álbuns que existia
/// antes), já que agora são o conteúdo principal da Home, não uma seção
/// secundária.
class _SecaoPlaylists extends StatelessWidget {
  final Future<_HomeDados> future;
  final VoidCallback onVoltar;

  const _SecaoPlaylists({required this.future, required this.onVoltar});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeDados>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 40, 16, 0),
            child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
          );
        }

        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Center(
              child: Text(
                'Não foi possível carregar suas playlists.\nPuxe pra baixo pra tentar de novo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        final dados = snapshot.data;
        final playlists = dados?.playlists ?? [];
        if (playlists.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Center(
              child: Text(
                'Nenhuma playlist ainda.\nPeça pra liberarem uma playlist pra você.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSecao('Suas playlists'),
            ...playlists.map(
              (p) => _PlaylistCard(
                playlist: p,
                novidade: dados?.novidades[p.id],
                onVoltar: onVoltar,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final PlaylistResumo playlist;
  final NovidadePlaylist? novidade;
  final VoidCallback onVoltar;

  const _PlaylistCard({
    required this.playlist,
    required this.novidade,
    required this.onVoltar,
  });

  @override
  Widget build(BuildContext context) {
    final capaUrl = playlist.capaUrl(AppConstants.driveApiKey);
    final novidade = this.novidade;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PlaylistScreen(playlistId: playlist.id, nome: playlist.nome),
            ),
          ).then((_) => onVoltar());
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: capaUrl != null
                      ? CachedNetworkImage(
                          imageUrl: capaUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          placeholder: (context, url) => const _CapaPlaylistPlaceholder(),
                          errorWidget: (context, url, error) =>
                              const _CapaPlaylistPlaceholder(),
                        )
                      : const _CapaPlaylistPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${playlist.totalFaixas} faixa${playlist.totalFaixas == 1 ? '' : 's'}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        if (novidade != null) ...[
                          const SizedBox(width: 8),
                          _SeloNovidade(novidade: novidade),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selo do card: "Playlist nova" ou "N músicas novas".
class _SeloNovidade extends StatelessWidget {
  final NovidadePlaylist novidade;

  const _SeloNovidade({required this.novidade});

  @override
  Widget build(BuildContext context) {
    final n = novidade.novas;
    final plural = n == 1 ? '' : 's';
    final texto = novidade.playlistNova
        ? 'Playlist nova'
        : '$n música$plural nova$plural';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _CapaPlaylistPlaceholder extends StatelessWidget {
  const _CapaPlaylistPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surfaceHigh,
      child: const Center(
        child: Icon(Icons.queue_music, color: AppTheme.accent, size: 24),
      ),
    );
  }
}
