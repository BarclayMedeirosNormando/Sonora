import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/pasta_conteudo.dart';

/// Comunicação com o backend (Web App do Apps Script).
class ApiService {
  /// Checa se o App_ID está liberado na planilha de controle.
  /// action=validar&id=XXX
  static Future<bool> validarId(String appId) async {
    final uri = Uri.parse(AppConstants.backendBaseUrl).replace(
      queryParameters: {'action': 'validar', 'id': appId},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Falha ao validar ID (HTTP ${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['liberado'] == true;
  }

  /// Lista o conteúdo direto de uma pasta do Drive: subpastas e faixas MP3.
  /// action=navegar&pasta=XXX
  static Future<PastaConteudo> navegarPasta(String pastaId) async {
    final uri = Uri.parse(AppConstants.backendBaseUrl).replace(
      queryParameters: {'action': 'navegar', 'pasta': pastaId},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Falha ao carregar a pasta (HTTP ${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PastaConteudo.fromJson(body);
  }

  /// Busca o cache pré-computado da biblioteca inteira (gerado por
  /// backend/CacheBiblioteca.gs) através do Web App — em vez de buscar o
  /// arquivo direto do Drive via alt=media, porque esse endpoint do Drive
  /// não garante cabeçalho CORS de forma confiável quando chamado de
  /// dentro de um navegador (Flutter Web), causando "Failed to fetch"
  /// intermitente. Passando pelo Web App (igual action=validar, que nunca
  /// deu esse problema) resolve de vez.
  /// action=cache
  static Future<Map<String, dynamic>> obterCacheBiblioteca() async {
    final uri = Uri.parse(AppConstants.backendBaseUrl).replace(
      queryParameters: {'action': 'cache'},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
        'Falha ao carregar o cache da biblioteca (HTTP ${response.statusCode})',
      );
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (body['erro'] != null) {
      throw Exception(body['erro']);
    }
    return body;
  }
}
