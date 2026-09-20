import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'home_screen.dart';

/// Casca do app: só a Home (playlists curadas) e o mini-player fixo
/// embaixo. Desde a v2.5.5 não existem mais as abas Buscar e Biblioteca
/// -- o usuário só vê o que foi selecionado pra ele na curadoria.
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: HomeScreen(),
      bottomNavigationBar: SafeArea(top: false, child: MiniPlayer()),
    );
  }
}
