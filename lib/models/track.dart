/// Uma faixa é um arquivo MP3 dentro de uma pasta no Google Drive.
class Track {
  final String id; // ID do arquivo no Drive
  final String title;
  final int sizeBytes;
  final String? paiId; // ID da pasta-pai — só vem preenchido quando veio da árvore completa (navegação de pastas)
  // Preenchidos quando a faixa vem de uma playlist curada (o backend já
  // entrega capa e nome do álbum prontos) -- assim o player não depende
  // mais do cache da biblioteca inteira pra mostrar capa/álbum.
  final String? capaId; // ID do arquivo de capa no Drive
  final String albumNome;

  const Track({
    required this.id,
    required this.title,
    this.sizeBytes = 0,
    this.paiId,
    this.capaId,
    this.albumNome = '',
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['name'] as String,
      sizeBytes: (json['size'] as num?)?.toInt() ?? 0,
      paiId: json['paiId'] as String?,
    );
  }

  /// Serialização simples pra salvar localmente (fila do player, histórico,
  /// "continuar de onde parou") — diferente do fromJson, que espera o
  /// formato que vem do backend (chaves "name"/"size").
  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'title': title,
        'sizeBytes': sizeBytes,
        'paiId': paiId,
        'capaId': capaId,
        'albumNome': albumNome,
      };

  factory Track.fromLocalJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'] as String,
      title: json['title'] as String,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      // Campo novo (30/08/2026) — estados salvos ANTES dessa mudança não
      // têm 'paiId' no JSON; o '?' + fallback null cobre esse caso sem
      // quebrar a restauração de filas salvas antigas.
      paiId: json['paiId'] as String?,
      // Campos novos (v2.5.5) -- estados salvos antes não têm, cai no padrão.
      capaId: json['capaId'] as String?,
      albumNome: json['albumNome'] as String? ?? '',
    );
  }

  /// URL da capa (herdada da playlist curada), ou null se não tiver.
  String? capaUrl(String apiKey) {
    if (capaId == null) return null;
    return 'https://www.googleapis.com/drive/v3/files/$capaId?alt=media&key=$apiKey';
  }

  /// URL de streaming via o proxy de mídia no Cloud Run (não mais direto
  /// do Drive, desde 30/08/2026 — ver sonora_deploy.md "proxy de mídia").
  /// O proxy guarda a faixa em cache (Cloud Storage) na primeira vez que
  /// alguém toca ela; todo mundo depois é servido do cache, sem bater no
  /// Drive de novo — evita o gatilho de anti-abuso do Drive quando muita
  /// gente toca a mesma faixa popular ao mesmo tempo.
  /// [appId] vai como query param -- desde o reforco de seguranca, o
  /// backend passou a exigir que o App_ID esteja liberado antes de
  /// servir a faixa (antes, qualquer um com a URL conseguia tocar/baixar
  /// qualquer musica, mesmo sem nunca ter passado pela validacao).
  String streamUrl(String cloudRunBaseUrl, String appId) =>
      '$cloudRunBaseUrl/midia/$id?appId=${Uri.encodeQueryComponent(appId)}';

  /// Título "limpo" pra exibição: remove a extensão .mp3 e, se existir, a
  /// mesma marca "Proprietário @..." que aparece em vários nomes de pasta
  /// (ver Album.displayName).
  String get displayTitle {
    var t = title;
    if (t.toLowerCase().endsWith('.mp3')) {
      t = t.substring(0, t.length - 4);
    }
    final idx = t.toLowerCase().indexOf('proprietário');
    if (idx >= 0) {
      t = t.substring(0, idx);
    }
    t = t.replaceAll('🎵', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? title : t;
  }
}
