import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';
import '../services/device_id_service.dart';
import '../services/offline_playlist_service.dart';
import '../services/player_service.dart';
import '../services/playlist_vistas_service.dart';
import '../widgets/aparece.dart';
import '../widgets/capa_placeholder.dart';
import '../widgets/estado_vazio.dart';
import '../widgets/skeletons.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Future<_HomeDados> _playlistsFuture;
  String? _appId;
  // Marca que a pessoa foi montar playlist no navegador -- ao voltar pro
  // app, a Home recarrega sozinha pra mostrar o que ela criou.
  bool _abriuCriador = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playlistsFuture = _carregarPlaylists();
    // Carregado separado da lista de playlists -- o App_ID já está em
    // cache local (DeviceIdService), então isso resolve quase instantâneo
    // e não precisa bloquear o resto da tela.
    DeviceIdService.getOrCreateDeviceId().then((id) {
      if (mounted) setState(() => _appId = id);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _abriuCriador) {
      _abriuCriador = false;
      _recarregar();
    }
  }

  /// Abre a página web onde a pessoa monta as próprias playlists, já com o
  /// ID deste aparelho (a página guarda o ID e limpa o endereço).
  Future<void> _abrirCriador() async {
    final id = _appId ?? await DeviceIdService.getOrCreateDeviceId();
    final url = Uri.parse(
      '${AppConstants.cloudRunBaseUrl}/minhaplaylist?id=${Uri.encodeQueryComponent(id)}',
    );
    var abriu = false;
    try {
      abriu = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      abriu = false;
    }
    if (!mounted) return;
    if (abriu) {
      _abriuCriador = true;
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra abrir o navegador.')),
      );
    }
  }

  Future<_HomeDados> _carregarPlaylists() async {
    // Lido antes do primeiro await, enquanto o context ainda é seguro.
    final offline = context.read<OfflinePlaylistService>();
    final appId = await DeviceIdService.getOrCreateDeviceId();
    final playlists = await ApiService.obterPlaylists(appId);
    final novidades = await PlaylistVistasService.verificar(playlists);
    // Modo offline: baixa o que entrou de novo nas playlists ligadas (roda
    // solto, sem segurar a Home).
    unawaited(offline.sincronizarTodas(playlists));
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
    HapticFeedback.selectionClick();
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
                color: AppTheme.textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: _recarregar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _Cabecalho(appId: _appId, onCopiar: _copiarAppId, onCriar: _abrirCriador),
            const _ContinuarOuvindo(),
            _SecaoPlaylists(
              future: _playlistsFuture,
              onVoltar: _aoVoltarDaPlaylist,
              onTentarDeNovo: _recarregar,
              onCriar: _abrirCriador,
            ),
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

/// Saudação + ID do aparelho (toque copia) -- o ID fica sempre visível pra
/// pessoa conseguir mandar de novo (ex: pra liberar outra playlist) sem
/// precisar desinstalar e reinstalar.
class _Cabecalho extends StatelessWidget {
  final String? appId;
  final VoidCallback onCopiar;
  final VoidCallback onCriar;

  const _Cabecalho({
    required this.appId,
    required this.onCopiar,
    required this.onCriar,
  });

  String get _saudacao {
    final hora = DateTime.now().hour;
    if (hora < 12) return 'Bom dia';
    if (hora < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    final id = appId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _saudacao,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'O que vamos ouvir hoje?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          if (id != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onCopiar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.surfaceHigh),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.badge_outlined, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 6),
                        Text(
                          'ID: $id',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.copy, size: 13, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onCriar,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_circle_outline, size: 16, color: AppTheme.accent),
                        SizedBox(width: 6),
                        Text(
                          'Criar minha playlist',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Card grande com a faixa que está tocando (ou pausada): capa, título,
/// play/pause e uma barrinha de progresso. Toque abre o player.
class _ContinuarOuvindo extends StatelessWidget {
  const _ContinuarOuvindo();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final faixa = player.faixaAtual;
    if (faixa == null) return const SizedBox.shrink();

    final capaUrl = faixa.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);
    const capaPadrao = CapaPlaceholder(semente: 'sonora', tamanhoIcone: 26);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accent.withValues(alpha: 0.16),
                  AppTheme.surface,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: capaUrl != null
                            ? CachedNetworkImage(
                                imageUrl: capaUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 160,
                                placeholder: (context, url) => capaPadrao,
                                errorWidget: (context, url, error) => capaPadrao,
                              )
                            : capaPadrao,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONTINUAR OUVINDO',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            faixa.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (faixa.albumNome.isNotEmpty)
                            Text(
                              faixa.albumNome,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppTheme.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          player.alternarPlayPause();
                        },
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(
                            player.tocando
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StreamBuilder<Duration>(
                  stream: player.posicaoStream,
                  builder: (context, snapshot) {
                    final posicao = snapshot.data ?? Duration.zero;
                    final duracao = player.duracao;
                    final progresso = duracao.inMilliseconds > 0
                        ? (posicao.inMilliseconds / duracao.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progresso,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lista as playlists curadas pra este App_ID -- cards grandes,
/// verticais, já que agora são o conteúdo principal da Home.
class _SecaoPlaylists extends StatelessWidget {
  final Future<_HomeDados> future;
  final VoidCallback onVoltar;
  final VoidCallback onTentarDeNovo;
  final VoidCallback onCriar;

  const _SecaoPlaylists({
    required this.future,
    required this.onVoltar,
    required this.onTentarDeNovo,
    required this.onCriar,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_HomeDados>(
      future: future,
      builder: (context, snapshot) {
        // Só mostra o esqueleto na primeira carga -- ao atualizar (puxar
        // pra baixo ou voltar de uma playlist) continua mostrando a lista.
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.only(top: 24),
            child: SkeletonPlaylists(),
          );
        }

        if (snapshot.hasError && !snapshot.hasData) {
          return EstadoVazio(
            icone: Icons.wifi_off_rounded,
            titulo: 'Não foi possível carregar',
            mensagem:
                'Verifique sua conexão. Sem internet, só abre o que já foi carregado antes.',
            rotuloAcao: 'Tentar de novo',
            aoAcionar: onTentarDeNovo,
          );
        }

        final dados = snapshot.data;
        final playlists = dados?.playlists ?? [];
        if (playlists.isEmpty) {
          return EstadoVazio(
            icone: Icons.queue_music,
            titulo: 'Nenhuma playlist ainda',
            mensagem:
                'Monte a sua, ou envie o seu ID (acima) pra liberarem uma playlist pra você.',
            rotuloAcao: 'Criar minha playlist',
            aoAcionar: onCriar,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloSecao('Suas playlists'),
            for (var i = 0; i < playlists.length; i++)
              Aparece(
                indice: i,
                child: _PlaylistCard(
                  playlist: playlists[i],
                  novidade: dados?.novidades[playlists[i].id],
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
    final capaUrl = playlist.capaUrl(AppConstants.cloudRunBaseUrl, DeviceIdService.idEmCache);
    final novidade = this.novidade;
    final offline = context.watch<OfflinePlaylistService>();
    final offlineAtivo = offline.estaAtiva(playlist.id);
    final offlineCompleto = offline.completa(playlist.id);
    final capaPadrao = CapaPlaceholder(semente: playlist.nome);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context)
                .push(
                  MaterialPageRoute(
                    builder: (_) =>
                        PlaylistScreen(playlistId: playlist.id, nome: playlist.nome),
                  ),
                )
                .then((_) => onVoltar());
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: capaUrl != null
                        ? CachedNetworkImage(
                            imageUrl: capaUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            placeholder: (context, url) => capaPadrao,
                            errorWidget: (context, url, error) => capaPadrao,
                          )
                        : capaPadrao,
                  ),
                ),
                const SizedBox(width: 14),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${playlist.totalFaixas} faixa${playlist.totalFaixas == 1 ? '' : 's'}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (novidade != null) _SeloNovidade(novidade: novidade),
                          if (offlineAtivo)
                            Icon(
                              offlineCompleto ? Icons.offline_pin : Icons.downloading,
                              size: 16,
                              color: AppTheme.accent,
                            ),
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
