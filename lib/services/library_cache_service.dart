import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/album.dart';
import '../models/pasta_conteudo.dart';
import '../models/track.dart';
import 'api_service.dart';
import 'device_id_service.dart';

/// Lê o cache pré-computado da biblioteca inteira (gerado pelo script
/// backend/CacheBiblioteca.gs, servido via ApiService.obterCacheBiblioteca
/// — direto do Drive fora da Web, via Apps Script na Web por causa de
/// CORS).
///
/// Usado pela Home ("adicionados recentemente"), pela Busca e também pela
/// navegação de pastas (FolderScreen) — a navegação pasta-a-pasta em si
/// não chama nada de rede, só filtra o que já está aqui.
///
/// Guarda tudo em memória durante a sessão do app, e também persiste no
/// aparelho (SharedPreferences) entre aberturas (28/08/2026): ao abrir o
/// app, mostra IMEDIATAMENTE o que já tinha salvo da última vez (sem
/// esperar rede nenhuma) e, se esse salvo estiver "velho" (mais de
/// [_ttlCache]), busca uma versão nova em segundo plano sem travar quem já
/// está vendo os dados salvos. Isso reduz bastante a frequência de
/// chamadas ao backend — a maioria das aberturas do app nem precisa de
/// rede pra mostrar a biblioteca. Use forcarRecarga pra pular tudo isso e
/// buscar na hora (ex: pull-to-refresh).
class LibraryCacheService {
  LibraryCacheService._();

  static const _prefsKeyCacheJson = 'sonora_cache_biblioteca_json';
  static const _prefsKeyCacheEm = 'sonora_cache_biblioteca_salvo_em';
  static const _ttlCache = Duration(hours: 1);

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

    final future = _carregar(forcarRecarga: forcarRecarga);
    _carregandoEmAndamento = future;
    try {
      await future;
    } finally {
      _carregandoEmAndamento = null;
    }
  }

  static Future<void> _carregar({required bool forcarRecarga}) async {
    final prefs = await SharedPreferences.getInstance();

    if (!forcarRecarga) {
      final jsonSalvo = prefs.getString(_prefsKeyCacheJson);
      if (jsonSalvo != null) {
        // Mostra o que já tinha salvo no aparelho na hora, sem esperar rede.
        await _aplicarBodyBruto(jsonSalvo);

        final salvoEmMs = prefs.getInt(_prefsKeyCacheEm);
        final salvoEm = salvoEmMs != null
            ? DateTime.fromMillisecondsSinceEpoch(salvoEmMs)
            : null;
        final estaFresco =
            salvoEm != null && DateTime.now().difference(salvoEm) < _ttlCache;
        if (estaFresco) return;

        // Salvo existe mas já passou do prazo: atualiza em segundo plano,
        // sem travar quem já está vendo os dados salvos — a próxima tela
        // ou reabertura do app já pega a versão nova.
        unawaited(_buscarDaRedeEAtualizar(prefs));
        return;
      }
    }

    // Primeira vez (nunca salvou nada localmente) ou recarga forçada
    // (pull-to-refresh): precisa esperar a rede.
    await _buscarDaRedeEAtualizar(prefs);
  }

  static Future<void> _buscarDaRedeEAtualizar(SharedPreferences prefs) async {
    try {
      final appId = await DeviceIdService.getOrCreateDeviceId();
      // obterCacheBiblioteca devolve o JSON BRUTO (texto), sem decodificar
      // -- a decodificacao (pesada, com a biblioteca podendo chegar a 200
      // mil faixas) acontece toda dentro de _aplicarBodyBruto, numa
      // isolate separada, pra nao travar a thread de UI. Guardar o texto
      // bruto direto (em vez de jsonEncode(body) de volta) tambem evita
      // decodificar e reencodar a mesma coisa duas vezes a toa.
      final jsonBruto = await ApiService.obterCacheBiblioteca(appId);
      await _aplicarBodyBruto(jsonBruto);
      await prefs.setString(_prefsKeyCacheJson, jsonBruto);
      await prefs.setInt(_prefsKeyCacheEm, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Se já tinha algo carregado (da própria memória ou de um cache
      // salvo lido agora há pouco), o app continua funcionando com aquilo
      // — só relança o erro se não tinha NADA pra mostrar ainda (primeira
      // vez, sem cache salvo e sem internet/backend disponível).
      if (_albunsEmCache == null) rethrow;
    }
  }

  /// Decodifica o JSON bruto do cache da biblioteca e monta as listas de
  /// álbuns/pastas/faixas, tudo rodando numa isolate separada via
  /// compute() (01/09/2026) -- antes, o jsonDecode + a montagem dos
  /// modelos rodavam direto na thread de UI. Com a biblioteca pequena
  /// (poucas mil faixas) isso era rápido demais pra notar, mas a meta é
  /// escalar pra ~200 mil faixas (ver sonora_deploy.md), e nesse tamanho
  /// um JSON de dezenas de MB decodificado na UI congelaria o app por um
  /// bom tempo -- bem no momento mais sensível, a abertura do app
  /// mostrando o cache salvo. compute() joga esse trabalho pesado numa
  /// isolate à parte, sem travar nenhum frame.
  static Future<void> _aplicarBodyBruto(String jsonBruto) async {
    final resultado = await compute(_decodificarBibliotecaEmIsolate, jsonBruto);
    _albunsEmCache = resultado.albuns;
    _arvorePastasEmCache = resultado.pastas;
    _arvoreFaixasEmCache = resultado.faixas;
  }

  /// Álbuns já em cache em memória, sem disparar rede — null se ainda não
  /// foi carregado nesta sessão. Útil pra telas que só querem mostrar algo
  /// se já tiver disponível (ex: Home não precisa aguardar carregamento).
  static List<Album>? get albunsSincronos => _albunsEmCache;

  /// TODAS as faixas da biblioteca (árvore inteira, não só uma pasta) já
  /// em cache em memória — null se ainda não carregou. Usado pela Busca
  /// pra encontrar música por nome, além de álbum/artista.
  static List<Track>? get faixasSincronas => _arvoreFaixasEmCache;

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


/// Resultado de [_decodificarBibliotecaEmIsolate] -- os três já vêm
/// prontos pra virar os caches em memória do LibraryCacheService.
class _ResultadoParseBiblioteca {
  final List<Album> albuns;
  final List<Album> pastas;
  final List<Track> faixas;

  _ResultadoParseBiblioteca(this.albuns, this.pastas, this.faixas);
}

/// Função de nível superior (exigência do compute() -- não pode ser
/// método de instância nem closure) que decodifica o JSON bruto do cache
/// da biblioteca e monta os modelos. Roda inteira numa isolate separada,
/// longe da thread de UI (ver comentário em _aplicarBodyBruto).
_ResultadoParseBiblioteca _decodificarBibliotecaEmIsolate(String jsonBruto) {
  final body = jsonDecode(jsonBruto) as Map<String, dynamic>;

  // ApiService.obterCacheBiblioteca não decodifica mais (ver comentário
  // lá) -- então essa checagem de erro, que antes rodava logo depois do
  // jsonDecode em api_service.dart, precisou vir pra cá.
  if (body['erro'] != null) {
    throw Exception(body['erro']);
  }

  final albunsJson = body['albuns'] as List<dynamic>? ?? [];
  final albuns = albunsJson
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

  return _ResultadoParseBiblioteca(albuns, pastas, faixas);
}
