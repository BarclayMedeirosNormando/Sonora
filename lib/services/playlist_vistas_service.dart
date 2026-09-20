import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';

/// Novidade de uma playlist desde a última vez que o usuário abriu ela:
/// [novas] é quantas faixas entraram; [playlistNova] é true quando a
/// playlist inteira é nova pra esse aparelho (aí [novas] é o total).
typedef NovidadePlaylist = ({int novas, bool playlistNova});

/// Lembra, por playlist, o que o usuário já viu -- pra avisar quando o
/// Barclay adiciona música nova na curadoria (selo no card da Home e
/// destaque nas faixas novas dentro da playlist). Tudo local
/// (SharedPreferences), não precisa de nada no backend.
///
/// Formato salvo: { playlistId: { "total": int, "ids": [fileId, ...] } }.
/// "ids" só existe depois que o usuário abre a playlist; antes disso (ex:
/// na primeira execução, quando a Home só "semeia" as contagens) só tem
/// o "total".
class PlaylistVistasService {
  PlaylistVistasService._();

  static const String _chave = 'sonora_playlists_vistas';

  static Future<Map<String, Map<String, dynamic>>> _ler(SharedPreferences prefs) async {
    final bruto = prefs.getString(_chave);
    if (bruto == null) return {};
    try {
      final mapa = jsonDecode(bruto) as Map<String, dynamic>;
      return mapa.map(
        (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _gravar(
    SharedPreferences prefs,
    Map<String, Map<String, dynamic>> mapa,
  ) async {
    await prefs.setString(_chave, jsonEncode(mapa));
  }

  /// Compara as playlists que a Home acabou de carregar com o que já foi
  /// visto. Na PRIMEIRA vez (nada salvo ainda) só registra as contagens
  /// atuais como "vistas" -- senão todo mundo que atualizasse o app veria
  /// tudo como novo. Só devolve entradas pras playlists que têm novidade.
  static Future<Map<String, NovidadePlaylist>> verificar(
    List<PlaylistResumo> playlists,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final primeiraVez = !prefs.containsKey(_chave);
      final mapa = await _ler(prefs);
      final resultado = <String, NovidadePlaylist>{};
      var mudou = false;

      for (final p in playlists) {
        final vista = mapa[p.id];
        if (vista == null) {
          if (primeiraVez) {
            mapa[p.id] = {'total': p.totalFaixas};
            mudou = true;
          } else if (p.totalFaixas > 0) {
            resultado[p.id] = (novas: p.totalFaixas, playlistNova: true);
          }
          continue;
        }
        final total = (vista['total'] as num?)?.toInt() ?? 0;
        if (p.totalFaixas > total) {
          resultado[p.id] = (novas: p.totalFaixas - total, playlistNova: false);
        }
      }

      if (mudou) await _gravar(prefs, mapa);
      return resultado;
    } catch (_) {
      // Aviso de novidade é só um extra -- nunca pode quebrar a Home.
      return {};
    }
  }

  /// Chamado quando o usuário abre a playlist: devolve os fileIds das
  /// faixas que são novas desde a última vez, e marca tudo como visto.
  static Future<Set<String>> marcarVista(Playlist playlist) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapa = await _ler(prefs);
      final atuais = playlist.faixas.map((f) => f.fileId).toList();
      final vista = mapa[playlist.id];
      var novas = <String>{};

      if (vista != null) {
        final idsSalvos = (vista['ids'] as List?)?.cast<String>().toSet();
        if (idsSalvos != null) {
          novas = atuais.where((id) => !idsSalvos.contains(id)).toSet();
        } else {
          // Só tem a contagem (semeada pela Home): assume que as faixas
          // novas entraram no fim da lista (é assim que a curadoria adiciona).
          final total = (vista['total'] as num?)?.toInt() ?? 0;
          final quantas = atuais.length - total;
          if (quantas > 0) novas = atuais.sublist(atuais.length - quantas).toSet();
        }
      }

      mapa[playlist.id] = {'total': atuais.length, 'ids': atuais};
      await _gravar(prefs, mapa);
      return novas;
    } catch (_) {
      return {};
    }
  }
}
