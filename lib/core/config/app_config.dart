import 'package:flutter/foundation.dart';

/// Configurações globais do app.
/// Altere este arquivo antes de gerar o APK.
class AppConfig {
  AppConfig._();

  /// URL base do servidor backend.
  /// Servidor local (PC na mesma rede Wi-Fi). Produção:
  /// 'https://relogio.neurelix.com.br'
  static String get serverApiUrl => kIsWeb
      ? Uri.base.origin
      : const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://60.60.61.219:6532',
        );

  /// Token de autenticação para a API do servidor (Bearer).
  /// Deve corresponder ao APP_AUTH_TOKEN no .env do servidor.
  static const String appAuthToken = kIsWeb
      ? ''
      : String.fromEnvironment(
          'APP_AUTH_TOKEN',
          defaultValue: 'dev-mobile-token',
        );

  /// Versão exibida em Ajustes → Sobre. Manter igual ao `version:` do pubspec.yaml.
  static const String appVersion = '1.0.0';
}
