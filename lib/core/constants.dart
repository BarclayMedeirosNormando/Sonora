/// Constantes globais do app Sonora.
class AppConstants {
  AppConstants._();

  /// Nome da versão exibido, pequeno e discreto, ao lado do nome
  /// "Sonora" na AppBar da Home. Atualizar junto com o `version:` do
  /// pubspec.yaml a cada novo build (só o nome curto, ex. "2.5.0",
  /// sem o +N de build number).
  static const String appVersionLabel = '2.5.5';

  /// URL do Web App do Apps Script (backend). Desde 29/08/2026 só é
  /// usada pelo endpoint legado action=navegar (não chamado pela
  /// navegação normal do app, ver LibraryCacheService) — validar/cache
  /// migraram pro Cloud Run (cloudRunBaseUrl abaixo), pra tirar de vez a
  /// dependência do limite de 30 execuções simultâneas do Apps Script.
  static const String backendBaseUrl =
      'https://script.google.com/macros/s/AKfycbxBSzA46eAFHaT_ckpayBL9vc6BjxNrABmD-yoX9ACVKZlYG1uNdGm4JrIa9CHAa8BM/exec';

  /// ID da pasta raiz no Google Drive (Meu Drive do Barclay) que contém
  /// os álbuns (subpastas) já migrados. Pasta "Sonora" — a partir de
  /// 23/08/2026 é daqui que o app busca as músicas.
  static const String rootFolderId = '14D3JK1VVyL3nyDNroK0s2vSLMC0H16I6';

  /// Chave usada no shared_preferences para persistir o App_ID gerado
  /// no primeiro uso do app.
  static const String prefsDeviceIdKey = 'sonora_device_id';

  /// Chave de API do Google Cloud (Google Drive API habilitada) usada pra
  /// montar as URLs de streaming dos MP3s (files/{id}?alt=media&key=...).
  /// A pasta de origem já está compartilhada como "qualquer pessoa com o
  /// link", então essa chave só precisa de acesso de leitura à Drive API.
  static const String driveApiKey = 'AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno';

  /// ID do arquivo JSON de cache da biblioteca (gerado pelo script
  /// backend/CacheBiblioteca.gs, função atualizarCacheBiblioteca() —
  /// preencher aqui com o ID que o log dessa função mostrar). Usado pela
  /// Home ("adicionados recentemente"), pela Busca e pela navegação de
  /// pastas (FolderScreen) — a navegação normal não passa mais pelo Apps
  /// Script, só a validação de acesso. Vazio = essas telas simplesmente
  /// não mostram nada do cache ainda, sem quebrar o resto do app.
  static const String libraryCacheFileId = '1Ks8PvbUfQqg75lHty2qb9bnoIvt7c4pP';

  /// URL base do backend em Google Cloud Run (item 4 do plano de escala
  /// — ver sonora_deploy.md nas notas do projeto). Desde 29/08/2026 é
  /// quem atende validar (checagem de acesso) e cache (biblioteca inteira
  /// no Flutter Web), além de registrar plays (telemetria pro painel
  /// administrativo) — tira a dependência do limite de 30 execuções
  /// simultâneas do Apps Script pros dois endpoints mais usados.
  static const String cloudRunBaseUrl =
      'https://sonora-backend-99445390129.us-central1.run.app';

  /// Número (com DDI 55 + DDD, só dígitos) que recebe os pedidos de
  /// música/álbum/artista mandados pela tela "Pedir música", via link
  /// wa.me — sem precisar de nenhuma API paga do WhatsApp.
  static const String whatsappPedidosNumero = '5583981309853';
}
