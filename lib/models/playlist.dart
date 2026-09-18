/// Uma faixa dentro de uma playlist curada — diferente de Track (que
/// representa um arquivo MP3 na árvore de pastas crua do Drive), aqui os
/// dados já vêm prontos do backend (playlists/{id}.faixas, ver server.js
/// do backend-cloudrun).
class PlaylistFaixa {
  final String fileId; // ID do arquivo MP3 no Drive
  final String nome;
  final String? albumId;
  final String albumNome;
  final String? capaId;

  const PlaylistFaixa({
    required this.fileId,
    required this.nome,
    this.albumId,
    this.albumNome = '',
    this.capaId,
  });

  factory PlaylistFaixa.fromJson(Map<String, dynamic> json) {
    return PlaylistFaixa(
      fileId: json['fileId'] as String,
      nome: json['nome'] as String,
      albumId: json['albumId'] as String?,
      albumNome: json['albumNome'] as String? ?? '',
      capaId: json['capaId'] as String?,
    );
  }
}

/// Resumo de uma playlist, como devolvido por GET /api/playlists — o
/// suficiente pra listar na Home, sem carregar as faixas ainda.
class PlaylistResumo {
  final String id;
  final String nome;
  final String? capaId;
  final int totalFaixas;

  const PlaylistResumo({
    required this.id,
    required this.nome,
    this.capaId,
    this.totalFaixas = 0,
  });

  factory PlaylistResumo.fromJson(Map<String, dynamic> json) {
    return PlaylistResumo(
      id: json['id'] as String,
      nome: json['nome'] as String,
      capaId: json['capaId'] as String?,
      totalFaixas: (json['totalFaixas'] as num?)?.toInt() ?? 0,
    );
  }

  /// URL da capa (definida pela primeira faixa adicionada na curadoria),
  /// ou null se a playlist ainda não tiver nenhuma faixa.
  String? capaUrl(String apiKey) {
    if (capaId == null) return null;
    return 'https://www.googleapis.com/drive/v3/files/$capaId?alt=media&key=$apiKey';
  }
}

/// Playlist completa, com as faixas — devolvida por GET /api/playlists/:id.
class Playlist {
  final String id;
  final String nome;
  final String? capaId;
  final List<PlaylistFaixa> faixas;

  const Playlist({
    required this.id,
    required this.nome,
    this.capaId,
    this.faixas = const [],
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      nome: json['nome'] as String,
      capaId: json['capaId'] as String?,
      faixas: (json['faixas'] as List<dynamic>? ?? [])
          .map((e) => PlaylistFaixa.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  String? capaUrl(String apiKey) {
    if (capaId == null) return null;
    return 'https://www.googleapis.com/drive/v3/files/$capaId?alt=media&key=$apiKey';
  }
}
