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
}
