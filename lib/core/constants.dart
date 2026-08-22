/// Constantes globais do app Sonora.
class AppConstants {
  AppConstants._();

  /// URL do Web App do Apps Script (backend).
  static const String backendBaseUrl =
      'https://script.google.com/macros/s/AKfycbxBSzA46eAFHaT_ckpayBL9vc6BjxNrABmD-yoX9ACVKZlYG1uNdGm4JrIa9CHAa8BM/exec';

  /// ID da pasta raiz no Google Drive (Meu Drive do Barclay) que contém
  /// os álbuns (subpastas) já migrados.
  static const String rootFolderId = '1p4U1_MANHrzEpoZu5iUAQn_Ng_phJuV7';

  /// Chave usada no shared_preferences para persistir o App_ID gerado
  /// no primeiro uso do app.
  static const String prefsDeviceIdKey = 'sonora_device_id';

  /// Chave de API do Google Cloud (Google Drive API habilitada) usada pra
  /// montar as URLs de streaming dos MP3s (files/{id}?alt=media&key=...).
  /// A pasta de origem já está compartilhada como "qualquer pessoa com o
  /// link", então essa chave só precisa de acesso de leitura à Drive API.
  static const String driveApiKey = 'AIzaSyA8gpiXcOLxKjGSVXuO_iF5NQRnKHwLwno';
}
