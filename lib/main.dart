import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
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

  // Habilita o serviço de mídia em primeiro plano do Android (notificação
  // de player + wake lock) — sem isso, o playback é suspenso pelo sistema
  // quando a tela bloqueia/o app vai pra segundo plano.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.barclaymedeiros.sonora.audio',
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
