import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger/app_logger.dart';

/// Relay RX messages to an external HTTP server.
class BleMessageRelayService {
  static final BleMessageRelayService _instance =
      BleMessageRelayService._internal();
  factory BleMessageRelayService() => _instance;
  BleMessageRelayService._internal();

  Future<void> sendRxMessage({
    required String baseUrl,
    required String content,
    String? deviceId,
    String? deviceName,
  }) async {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return;

    final uri = _buildUri(trimmed);
    final payload = <String, dynamic>{
      'content': content,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warning(
          'Falha ao enviar RX para servidor: ${response.statusCode}',
        );
      }
    } catch (e) {
      AppLogger.warning('Erro ao enviar RX para servidor: $e');
    }
  }

  Uri _buildUri(String baseUrl) {
    final normalized = baseUrl.startsWith('http://') ||
            baseUrl.startsWith('https://')
        ? baseUrl
        : 'http://$baseUrl';
    final uri = Uri.parse(normalized);

    final path = uri.path;
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/api/messages');
    }
    if (path.endsWith('/api/messages') || path == '/api/messages') {
      return uri;
    }
    if (path.endsWith('/api')) {
      return uri.replace(path: '${path}/messages');
    }
    return uri.replace(path: '${path}/api/messages');
  }
}
