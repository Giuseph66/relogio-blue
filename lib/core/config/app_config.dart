/// Configurações globais do app.
/// Altere este arquivo antes de gerar o APK.
class AppConfig {
  AppConfig._();

  /// URL base do servidor backend.
  static const String serverApiUrl = 'https://relogio.neurelix.com.br';

  /// Token de autenticação para a API do servidor (Bearer).
  /// Deve corresponder ao APP_AUTH_TOKEN no .env do servidor.
  static const String appAuthToken = 'dev-mobile-token';
}
