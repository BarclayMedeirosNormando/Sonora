import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'core/app_keys.dart';
import 'core/theme.dart';
import 'screens/validation_screen.dart';
import 'services/download_service.dart';
import 'services/favoritos_service.dart';
import 'services/historico_service.dart';
import 'services/player_service.dart';

void main() async {
  // Precisa estar pronto antes de usar SharedPreferences/plugins abaixo,
  // já que main() agora faz await antes do runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // No Android 13+ (API 33+), sem essa permissão concedida pelo usuário
  // a notificação do player em segundo plano NUNCA aparece — mesmo com o
  // foreground service rodando por baixo. Sem notificação visível, o
  // Android (e principalmente MIUI/HyperOS da Xiaomi) trata o app como
  // "inativo" e mata o processo depois de alguns minutos em segundo
  // plano, mesmo tocando música. Pedida antes do JustAudioBackground.init
  // pra já valer pro canal de notificação criado logo em seguida. Não se
  // aplica na Web (kIsWeb) — lá não existe foreground service/notificação.
  if (!kIsWeb) {
    await Permission.notification.request();
  }

  // Habilita o serviço de mídia em primeiro plano do Android (notificação
  // de player + wake lock) — sem isso, o playback é suspenso pelo sistema
  // quando a tela bloqueia/o app vai pra segundo plano.
  await JustAudioBackground.init(
    // ID novo (v2, 30/08/2026) de propósito — o canal antigo
    // ('com.barclaymedeiros.sonora.audio', existente desde a v2.1.0, antes
    // da gente pedir a permissão de notificação direito) pode ter ficado
    // silenciado por baixo dos panos (MIUI costuma bloquear canal por
    // canal, separado do interruptor geral do app) sem dar pra saber de
    // fora — trocar o ID força o Android a criar um canal novo do zero,
    // com o padrão (permitido), em vez de herdar esse possível bloqueio.
    androidNotificationChannelId: 'com.barclaymedeiros.sonora.audio.v2',
    androidNotificationChannelName: 'Reprodução Sonora',
    androidNotificationOngoing: true,
  );

  // Criado antes do MultiProvider pra poder ser injetado tanto no próprio
  // Provider (telas usam context.watch/read normalmente) quanto direto no
  // construtor do PlayerService (que não tem acesso a context). Esperamos
  // o carregamento do mapa de downloads terminar ANTES do runApp() pra
  // garantir que o PlayerService, ao restaurar o estado salvo, já enxergue
  // corretamente quais faixas estão baixadas (sem essa espera, dava pra
  // cair numa corrida em que o player achava que uma faixa baixada ainda
  // não tinha download e tentava tocar via streaming, mesmo offline).
  final downloadService = DownloadService();
  await downloadService.inicializar();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: downloadService),
        ChangeNotifierProvider(
          create: (_) => PlayerService(downloadService: downloadService),
        ),
        ChangeNotifierProvider(create: (_) => FavoritosService()),
        ChangeNotifierProvider(create: (_) => HistoricoService()),
      ],
      child: const SonoraApp(),
    ),
  );
}

class SonoraApp extends StatelessWidget {
  const SonoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sonora',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.dark,
      home: const ValidationScreen(),
    );
  }
}
