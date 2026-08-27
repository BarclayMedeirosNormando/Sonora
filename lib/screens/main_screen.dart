import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../widgets/mini_player.dart';
import 'folder_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';

/// Casca de navegação principal do app: 3 abas fixas (Início, Buscar,
/// Biblioteca), estilo Spotify. O mini-player fica sempre visível acima
/// da barra de abas, em vez de cada tela precisar do seu próprio. Usa
/// IndexedStack pra cada aba manter seu estado (scroll, resultado de
/// busca etc.) ao trocar de aba, em vez de recriar a tela toda vez.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _indice = 0;

  final List<Widget> _paginas = const [
    HomeScreen(),
    SearchScreen(),
    FolderScreen(
      folderId: AppConstants.rootFolderId,
      title: 'Biblioteca',
      mostrarMiniPlayer: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _indice, children: _paginas),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            currentIndex: _indice,
            onTap: (indice) => setState(() => _indice = indice),
            type: BottomNavigationBarType.fixed,
            backgroundColor: AppTheme.surfaceHigh,
            selectedItemColor: AppTheme.accent,
            unselectedItemColor: AppTheme.textSecondary,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Início'),
              BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Buscar'),
              BottomNavigationBarItem(
                icon: Icon(Icons.library_music),
                label: 'Biblioteca',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
