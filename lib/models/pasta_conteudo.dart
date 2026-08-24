import 'album.dart';
import 'track.dart';

/// Conteúdo de uma pasta do Drive: as subpastas e as faixas MP3 que estão
/// diretamente dentro dela (um nível só — navegação em profundidade é feita
/// chamando de novo pra cada subpasta que o usuário abrir).
class PastaConteudo {
  final List<Album> pastas;
  final List<Track> faixas;

  const PastaConteudo({required this.pastas, required this.faixas});

  factory PastaConteudo.fromJson(Map<String, dynamic> json) {
    final pastasJson = json['pastas'] as List<dynamic>? ?? [];
    final faixasJson = json['faixas'] as List<dynamic>? ?? [];
    return PastaConteudo(
      pastas: pastasJson
          .map((p) => Album.fromJson(p as Map<String, dynamic>))
          .toList(),
      faixas: faixasJson
          .map((f) => Track.fromJson(f as Map<String, dynamic>))
          .toList(),
    );
  }
}
