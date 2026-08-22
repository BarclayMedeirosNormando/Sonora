import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'screens/validation_screen.dart';
import 'services/favoritos_service.dart';
import 'services/historico_service.dart';
import 'services/player_service.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerService()),
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
      theme: AppTheme.dark,
      home: const ValidationScreen(),
    );
  }
}
