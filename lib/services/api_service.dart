import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/pasta_conteudo.dart';

/// Comunicação com o backend (Web App do Apps Script) e, quando possível,
/// direto com o Google Drive.
class ApiService {
  /// Checa se o App_ID está liberado na planilha de controle.
  /// action=validar&id=XXX
  static Future<bool> validarId(String appId) async {
    return _comRetentativas(() async {
      final uri = Uri.parse('${AppConstants.cloudRunBaseUrl}/validar').replace(
        queryParameters: {'id': appId},
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Falha ao validar ID (HTTP ${response.statusCode})');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['liberado'] == true;
    });
  }

  /// Lista o conteúdo direto de uma pasta do Drive: subpastas e faixas MP3.
  /// action=navegar&pasta=XXX — legado, não usado mais pela navegação
  /// normal (ver LibraryCacheService), mantido só por segurança.
  static Future<PastaConteudo> navegarPasta(String pastaId) async {
    return _comRetentativas(() async {
      final uri = Uri.parse(AppConstants.backendBaseUrl).replace(
        queryParameters: {'action': 'navegar', 'pasta': pastaId},
      );
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception('Falha ao carregar a pasta (HTTP ${response.statusCode})');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return PastaConteudo.fromJson(body);
    });
  }

  /// Busca o cache pré-computado da biblioteca inteira (gerado por
  /// backend/CacheBiblioteca.gs).
  ///
  /// No Flutter Web passa pelo Web App (action=cache) porque o endpoint
  /// alt=media do Drive não garante cabeçalho CORS de forma confiável
  /// quando chamado de dentro de um navegador ("Failed to fetch"
  /// intermitente — corrigido em 27/08/2026).
  ///
  /// Fora da Web (Android/iOS/desktop nativo) não existe essa restrição de
  /// CORS — então busca DIRETO do Drive, sem passar pelo Apps Script
  /// (28/08/2026). Isso tira a chamada mais pesada (o JSON inteiro da
  /// biblioteca) do Apps Script, que tem limite de 30 execuções
  /// simultâneas em contas Google normais — sobra só o action=validar
  /// (rápido) passando por lá, reduzindo bastante o risco de esbarrar
  /// nesse limite com muita gente abrindo o app ao mesmo tempo.
  /// Devolve o JSON BRUTO (texto), sem decodificar -- desde 01/09/2026 a
  /// decodificação (pesada, biblioteca podendo chegar a 200 mil faixas)
  /// acontece numa isolate separada dentro do LibraryCacheService, não
  /// aqui, pra não travar a thread de UI. Quem chama também precisa
  /// checar o campo "erro" por conta própria depois de decodificar (isso
  /// também passou a acontecer do lado de quem decodifica).
  static Future<String> obterCacheBiblioteca(String appId) async {
    return _comRetentativas(() async {
      // Sempre via Cloud Run (mudou em 30/08/2026 — antes, fora da Web,
      // ia direto no Drive com alt=media&key=..., mesmo padrão de URL
      // usado pro streaming de faixa que já causou bloqueio por
      // anti-abuso do Drive (ver sonora_proxy_midia.md). Um HTTP 403
      // batendo direto nesse endpoint quebrava a Biblioteca inteira sem
      // aviso. Centralizar no Cloud Run não elimina o uso da mesma
      // DRIVE_API_KEY por baixo, mas concentra as chamadas numa única
      // origem confiável (o servidor) em vez de cada celular batendo
      // direto no Drive.
      // appId vai junto desde o reforco de seguranca: o backend agora
      // exige que o App_ID esteja liberado antes de devolver o
      // catalogo -- antes, /cache respondia pra qualquer um, sem checar
      // liberacao nenhuma.
      final uri = Uri.parse('${AppConstants.cloudRunBaseUrl}/cache').replace(
        queryParameters: {'appId': appId},
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw Exception(
          'Falha ao carregar o cache da biblioteca (HTTP ${response.statusCode})',
        );
      }
      return utf8.decode(response.bodyBytes);
    });
  }

  /// Registra que uma faixa começou a tocar de verdade — telemetria pro
  /// painel administrativo (seção Engajamento, ver backend-cloudrun/). Sem
  /// retentativas e sem propagar erro: se o Cloud Run estiver fora do ar
  /// ou sem rede, isso nunca deve afetar a reprodução — falha em silêncio.
  static Future<void> registrarPlay({
    required String appId,
    required String faixaId,
    required String faixaNome,
    String albumNome = '',
  }) async {
    try {
      final uri = Uri.parse('${AppConstants.cloudRunBaseUrl}/registrar-play');
      await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'appId': appId,
              'faixaId': faixaId,
              'faixaNome': faixaNome,
              'albumNome': albumNome,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Telemetria — nunca deve afetar a reprodução.
    }
  }

  /// Tenta [tentativa] até 3 vezes no total, com uma pequena espera entre
  /// cada uma — suaviza picos passageiros (ex: Apps Script esbarrando no
  /// limite de 30 execuções simultâneas, ou uma instabilidade rápida de
  /// rede) sem precisar que o usuário perceba ou aperte "Tentar de novo"
  /// manualmente. Se todas as tentativas falharem, deixa o erro da última
  /// propagar normalmente (quem chamou trata do jeito que já tratava).
  static Future<T> _comRetentativas<T>(Future<T> Function() tentativa) async {
    const atrasos = [Duration(milliseconds: 800), Duration(milliseconds: 1600)];
    for (final atraso in atrasos) {
      try {
        return await tentativa();
      } catch (_) {
        await Future.delayed(atraso);
      }
    }
    return tentativa();
  }
}
