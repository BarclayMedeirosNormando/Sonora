/// Uma pasta do Drive (pode ser um gênero, uma coleção ou um álbum de
/// verdade — a estrutura real varia de profundidade, então esse modelo é
/// usado de forma genérica pelo navegador de pastas).
class Album {
  final String id; // ID da pasta no Drive
  final String name; // Nome da pasta
  final String? capaId; // ID do arquivo de imagem de capa dentro da pasta (se houver)

  const Album({
    required this.id,
    required this.name,
    this.capaId,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: json['name'] as String,
      capaId: json['capaId'] as String?,
    );
  }

  /// Nome "limpo" pra exibição: várias pastas de origem vêm com uma marca
  /// tipo "🎵 Nome 🎵 Proprietário @alguem" embutida no próprio nome da
  /// pasta. Isso remove o "Proprietário @..." e os emojis de separador.
  String get displayName {
    final idx = name.toLowerCase().indexOf('proprietário');
    final semMarca = idx >= 0 ? name.substring(0, idx) : name;
    final limpo = semMarca.replaceAll('🎵', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return limpo.isEmpty ? name : limpo;
  }

  /// URL pra baixar a imagem de capa direto do Drive, ou null se a pasta
  /// não tiver nenhuma imagem dentro.
  String? capaUrl(String apiKey) {
    if (capaId == null) return null;
    return 'https://www.googleapis.com/drive/v3/files/$capaId?alt=media&key=$apiKey';
  }
}
