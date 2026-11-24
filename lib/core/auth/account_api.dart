import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// Refusal from the server, with a message ready to show to the user.
/// Network failures surface as the original exception instead.
class AccountException implements Exception {
  final int status;
  final String message;
  const AccountException(this.status, this.message);

  @override
  String toString() => message;
}

class AppAccount {
  final String id;
  final String email;
  const AppAccount({required this.id, required this.email});
}

class RemoteProfile {
  final Map<String, dynamic> profile;
  final int revision;

  /// True when the write was refused: these are the server's current values.
  final bool conflict;
  const RemoteProfile(this.profile, this.revision, {this.conflict = false});
}

/// `/api/account`: the PWA authenticates with an HttpOnly cookie, the native
/// app with the account token.
class AccountApi {
  static http.Client client = http.Client();
  static const _timeout = Duration(seconds: 8);

  static Future<(AppAccount, String?)> authenticate(
    String email,
    String password, {
    required bool register,
  }) async {
    final data = await _send('POST', register ? 'register' : 'login', body: {
      'email': email,
      'password': password,
      if (!kIsWeb) 'client': 'native',
    });
    return (_account(data['user'] as Map), data['token'] as String?);
  }

  /// Administrator session token for the native app; null when refused.
  static Future<String?> adminLogin(String email, String password) async {
    final (status, data) = await _request('POST', 'login',
        base: '/api/admin/auth',
        body: {'email': email, 'password': password, 'client': 'native'});
    if (status == 401) return null;
    _check(status, data);
    return data['token'] as String?;
  }

  static Future<AppAccount?> session() async {
    final user = (await _send('GET', 'session'))['user'];
    return user == null ? null : _account(user as Map);
  }

  static Future<void> logout(String? token) =>
      _send('POST', 'logout', token: token, body: const {});

  static Future<void> delete(String? token, String password) =>
      _send('DELETE', '', token: token, body: {'password': password});

  static Future<RemoteProfile> getProfile(String? token) async =>
      _profile(await _send('GET', 'profile', token: token));

  static Future<RemoteProfile> putProfile(
    String? token,
    Map<String, dynamic> profile,
    int revision,
  ) async {
    final (status, data) = await _request('PUT', 'profile',
        token: token, body: {'profile': profile, 'revision': revision});
    if (status == 409) return _profile(data, conflict: true);
    _check(status, data);
    return _profile(data);
  }

  static AppAccount _account(Map user) =>
      AppAccount(id: user['id'] as String, email: user['email'] as String);

  static RemoteProfile _profile(Map<String, dynamic> data,
          {bool conflict = false}) =>
      RemoteProfile(
        Map<String, dynamic>.from(data['profile'] as Map),
        data['revision'] as int,
        conflict: conflict,
      );

  static Future<Map<String, dynamic>> _send(String method, String path,
      {String? token, Map<String, dynamic>? body}) async {
    final (status, data) =
        await _request(method, path, token: token, body: body);
    _check(status, data);
    return data;
  }

  static void _check(int status, Map<String, dynamic> data) {
    if (status >= 200 && status < 300) return;
    throw AccountException(
      status,
      status < 500 && data['error'] is String
          ? data['error'] as String
          : 'Servidor indisponível. Tente novamente.',
    );
  }

  static Future<(int, Map<String, dynamic>)> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    String base = '/api/account',
  }) async {
    final server = AppConfig.serverApiUrl.replaceAll(RegExp(r'/+$'), '');
    final request = http.Request(
      method,
      Uri.parse('$server$base${path.isEmpty ? '' : '/$path'}'),
    );
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await (() async =>
        http.Response.fromStream(await client.send(request)))()
        .timeout(_timeout);
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      // Proxy error pages are HTML; the status code is enough.
    }
    if (decoded is Map<String, dynamic>) return (response.statusCode, decoded);
    // A 2xx without JSON is not our API (e.g. captive portal).
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    return (ok ? 502 : response.statusCode, const <String, dynamic>{});
  }
}
