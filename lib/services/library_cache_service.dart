import '../models/album.dart';
import '../models/pasta_conteudo.dart';
import '../models/track.dart';
import 'api_service.dart';

/// Lê o cache pré-computado da biblioteca inteira (gerado pelo script
/// backend/CacheBiblioteca.gs) através do Web App (action=cache, ver
/// ApiService.obterCacheBiblioteca) — mudou de buscar direto do Drive via
/// API key (27/08/2026) porque o endpoint alt=media do Drive não garante
/// CORS de forma confiável quando chamado de um navegador (Flutter Web).
/// Usado pela Home ("adicionados recentemente"), pela Busca e também pela
/// navegação de pastas (FolderScreen) — que antes chamava o Apps Script a
/// cada pasta aberta e podia esbarrar no limite de 30 execuções
/// simultâneas do script com muita gente navegando ao mesmo tempo; agora
/// só esse fetch do cache passa pelo Web App (uma vez, guardado em
/// memória) — a navegação pasta-a-pasta em si não chama o Apps Script.
///
/// Guarda tudo em memória durante a sessão do app; use forcarRecarga pra
/// puxar de novo (ex: pull-to-refresh).
class LibraryCacheService {
  LibraryCacheService._();

  static List<Album>? _albunsEmCache;
  static List<Album>? _arvorePastasEmCache;
  static List<Track>? _arvoreFaixasEmCache;
  static Future<void>? _carregandoEmAndamento;

  static Future<List<Album>> obterAlbuns({bool forcarRecarga = false}) async {
    await _garantirCarregado(forcarRecarga: forcarRecarga);
    return _albunsEmCache ?? [];
  }

  /// Subpastas e faixas diretamente dentro de [pastaId] — equivalente ao
  /// que o backend retornava em action=navegar, mas filtrado localmente a
  /// partir do cache já baixado, sem nenhuma chamada ao Apps Script.
  static Future<PastaConteudo> obterConteudoDaPasta(
    String pastaId, {
    bool forcarRecarga = false,
  }) async {
    await _garantirCarregado(forcarRecarga: forcarRecarga);

    final pastas = (_arvorePastasEmCache ?? [])
        .where((p) => p.paiId == pastaId)
        .toList()
      ..sort((a, b) => _compararNatural(a.name, b.name));

    final faixas = (_arvoreFaixasEmCache ?? [])
        .where((t) => t.paiId == pastaId)
        .toList()
      ..sort((a, b) => _compararNatural(a.title, b.title));

    return PastaConteudo(pastas: pastas, faixas: faixas);
  }

  static Future<void> _garantirCarregado({required bool forcarRecarga}) async {
    if (!forcarRecarga && _albunsEmCache != null) return;

    // Evita que duas telas carregando ao mesmo tempo (ex: Home e Busca na
    // primeira abertura do app) disputem pra baixar o mesmo arquivo duas
    // vezes em paralelo.
    if (_carregandoEmAndamento != null) {
      await _carregandoEmAndamento;
      return;
    }

    final future = _carregar();
    _carregandoEmAndamento = future;
    try {
      await future;
    } finally {
      _carregandoEmAndamento = null;
    }
  }

  static Future<void> _carregar() async {
    final body = await ApiService.obterCacheBiblioteca();

    final albunsJson = body['albuns'] as List<dynamic>? ?? [];
    _albunsEmCache = albunsJson
        .map((a) => Album.fromJson(a as Map<String, dynamic>))
        .toList();

    final arvoreJson = body['arvore'] as List<dynamic>? ?? [];
    final pastas = <Album>[];
    final faixas = <Track>[];
    for (final item in arvoreJson) {
      final mapa = item as Map<String, dynamic>;
      if (mapa['tipo'] == 'pasta') {
        pastas.add(Album.fromJson(mapa));
      } else if (mapa['tipo'] == 'faixa') {
        faixas.add(Track.fromJson(mapa));
      }
    }
    _arvorePastasEmCache = pastas;
    _arvoreFaixasEmCache = faixas;
  }

  /// Álbuns já em cache em memória, sem disparar rede — null se ainda não
  /// foi carregado nesta sessão. Útil pra telas que só querem mostrar algo
  /// se já tiver disponível (ex: Home não precisa aguardar carregamento).
  static List<Album>? get albunsSincronos => _albunsEmCache;

  /// Álbum (pasta) correspondente a [id], procurado no cache já carregado
  /// em memória — usado pra achar a capa da pasta que contém a faixa que
  /// está tocando agora (Track só guarda paiId, não capaId). Retorna null
  /// se o cache ainda não carregou ou se a pasta não aparecer na árvore
  /// (ex: ela é a própria pasta raiz).
  static Album? albumPorId(String id) {
    for (final album in _arvorePastasEmCache ?? const <Album>[]) {
      if (album.id == id) return album;
    }
    for (final album in _albunsEmCache ?? const <Album>[]) {
      if (album.id == id) return album;
    }
    return null;
  }

  /// Ordenação "natural" (números dentro do nome comparados como número,
  /// não caractere por caractere) — pra "Faixa 2" vir antes de "Faixa 10",
  /// igual o comportamento que o Apps Script tinha com localeCompare
  /// numeric:true.
  static int _compararNatural(String a, String b) {
    final regex = RegExp(r'(\d+)|(\D+)');
    final partsA = regex.allMatches(a).map((m) => m.group(0)!).toList();
    final partsB = regex.allMatches(b).map((m) => m.group(0)!).toList();
    final len = partsA.length < partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < len; i++) {
      final na = int.tryParse(partsA[i]);
      final nb = int.tryParse(partsB[i]);
      final cmp = (na != null && nb != null)
          ? na.compareTo(nb)
          : partsA[i].toLowerCase().compareTo(partsB[i].toLowerCase());
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }
}
