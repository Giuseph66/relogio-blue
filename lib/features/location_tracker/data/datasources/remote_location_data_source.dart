import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../domain/entities/tracked_location.dart';
import '../../domain/entities/location_question.dart';

/// Fetches locations from the server filtered by the device's current position.
class RemoteLocationDataSource {
  final String baseUrl;
  final Duration timeout;

  const RemoteLocationDataSource({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 8),
  });

  /// Fetches locations from [/api/location/resolve] filtered by [latitude]/[longitude]
  /// and optionally [city]. Only locations whose city or geofence radius matches
  /// the current position are returned.
  Future<List<TrackedLocation>> fetchLocations({
    required double latitude,
    required double longitude,
    String? city,
  }) async {
    final uri = _buildBaseUri().replace(path: _buildBaseUri().path + '/api/location/resolve');

    final body = <String, dynamic>{
      'deviceId': 'mobile-app',
      'latitude': latitude,
      'longitude': longitude,
    };
    if (city != null && city.isNotEmpty) body['city'] = city;

    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('RemoteLocationDataSource: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (decoded['locations'] as List<dynamic>?) ?? [];
    return list.map((j) => TrackedLocation.fromJson(j as Map<String, dynamic>)).toList();
  }

  /// Fetches questions for a specific location/city from the resolve endpoint.
  Future<List<LocationQuestion>> fetchQuestionsForVisit({
    required double latitude,
    required double longitude,
    String? city,
  }) async {
    final uri = _buildBaseUri().replace(path: _buildBaseUri().path + '/api/location/resolve');

    final body = <String, dynamic>{
      'deviceId': 'mobile-app',
      'latitude': latitude,
      'longitude': longitude,
    };
    if (city != null && city.isNotEmpty) body['city'] = city;

    final response = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('RemoteLocationDataSource: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final list = (decoded['questions'] as List<dynamic>?) ?? [];
    return list
        .map((j) => LocationQuestion.fromJson(j as Map<String, dynamic>))
        .where((q) => q.options.length >= 2)
        .toList();
  }

  Uri _buildBaseUri() {
    final normalized = baseUrl.startsWith('http://') || baseUrl.startsWith('https://')
        ? baseUrl
        : 'http://$baseUrl';
    return Uri.parse(normalized.trimRight().replaceAll(RegExp(r'/$'), ''));
  }
}
