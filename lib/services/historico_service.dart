import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Uma pasta recém-aberta pelo usuário (registrada no histórico).
class HistoricoPasta {
  final String id;
  final String name;

  const HistoricoPasta({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory HistoricoPasta.fromJson(Map<String, dynamic> json) => HistoricoPasta(
        id: json['id'] as String,
        name: json['name'] as String,
      );
}

/// Histórico local de pastas e faixas recentemente abertas/tocadas — mostra
/// as mais recentes primeiro, sem duplicar (reabrir/tocar de novo move pro
/// topo). Só local, sem chamada ao backend.
class HistoricoService extends ChangeNotifier {
  static const _prefsKeyPastas = 'sonora_historico_pastas';
  static const _prefsKeyFaixas = 'sonora_historico_faixas';
  static const _maxItens = 30;

  final List<HistoricoPasta> _pastas = [];
  final List<Track> _faixas = [];

  List<HistoricoPasta> get pastas => List.unmodifiable(_pastas);
  List<Track> get faixas => List.unmodifiable(_faixas);

  HistoricoService() {
    _carregar();
  }

  Future<void> registrarPasta(String id, String name) async {
    _pastas.removeWhere((p) => p.id == id);
    _pastas.insert(0, HistoricoPasta(id: id, name: name));
    if (_pastas.length > _maxItens) {
      _pastas.removeRange(_maxItens, _pastas.length);
    }
    notifyListeners();
    await _salvar();
  }

  Future<void> registrarFaixa(Track track) async {
    _faixas.removeWhere((t) => t.id == track.id);
    _faixas.insert(0, track);
    if (_faixas.length > _maxItens) {
      _faixas.removeRange(_maxItens, _faixas.length);
    }
    notifyListeners();
    await _salvar();
  }

  Future<void> limpar() async {
    _pastas.clear();
    _faixas.clear();
    notifyListeners();
    await _salvar();
  }

  Future<void> _salvar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyPastas,
      jsonEncode(_pastas.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(
      _prefsKeyFaixas,
      jsonEncode(_faixas.map((t) => t.toLocalJson()).toList()),
    );
  }

  Future<void> _carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final brutoPastas = prefs.getString(_prefsKeyPastas);
      if (brutoPastas != null) {
        final lista = jsonDecode(brutoPastas) as List;
        _pastas
          ..clear()
          ..addAll(lista.map((e) => HistoricoPasta.fromJson(e as Map<String, dynamic>)));
      }

      final brutoFaixas = prefs.getString(_prefsKeyFaixas);
      if (brutoFaixas != null) {
        final lista = jsonDecode(brutoFaixas) as List;
        _faixas
          ..clear()
          ..addAll(lista.map((e) => Track.fromLocalJson(e as Map<String, dynamic>)));
      }

      notifyListeners();
    } catch (_) {
      // Histórico salvo inválido/corrompido — ignora e começa do zero.
    }
  }
}
