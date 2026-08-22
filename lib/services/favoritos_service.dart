import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Uma pasta marcada como favorita (guarda só o necessário pra navegar
/// direto nela e mostrar o nome, sem precisar buscar de novo no backend).
class FavoritoItem {
  final String id;
  final String name;

  const FavoritoItem({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory FavoritoItem.fromJson(Map<String, dynamic> json) => FavoritoItem(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

/// Lista de pastas favoritas, salva no aparelho (shared_preferences) — não
/// depende do backend, então não pesa em nada na navegação.
class FavoritosService extends ChangeNotifier {
  static const _prefsKey = 'sonora_favoritos';

  List<FavoritoItem> _favoritos = [];

  FavoritosService() {
    _carregar();
  }

  List<FavoritoItem> get favoritos => List.unmodifiable(_favoritos);

  bool ehFavorito(String id) => _favoritos.any((f) => f.id == id);

  Future<void> _carregar() async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = prefs.getString(_prefsKey);
    if (bruto != null) {
      final lista = jsonDecode(bruto) as List;
      _favoritos =
          lista.map((e) => FavoritoItem.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    }
  }

  Future<void> alternar(String id, String name) async {
    if (ehFavorito(id)) {
      _favoritos.removeWhere((f) => f.id == id);
    } else {
      _favoritos.add(FavoritoItem(id: id, name: name));
    }
    notifyListeners();
    await _salvar();
  }

  Future<void> remover(String id) async {
    _favoritos.removeWhere((f) => f.id == id);
    notifyListeners();
    await _salvar();
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    final bruto = jsonEncode(_favoritos.map((f) => f.toJson()).toList());
    await prefs.setString(_prefsKey, bruto);
  }
}
