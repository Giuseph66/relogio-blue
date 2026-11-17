import 'dart:convert';
import 'package:geocoding/geocoding.dart' show Placemark, Location;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

Future<List<dynamic>> _request(Map<String, String> query) async {
  final uri = Uri.parse(
    '${AppConfig.serverApiUrl}/api/geocoding',
  ).replace(queryParameters: query);
  final response = await http.get(uri).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw StateError(
      'Não foi possível consultar o endereço (${response.statusCode}).',
    );
  }
  return jsonDecode(response.body) as List<dynamic>;
}

Future<List<Placemark>> placemarkFromCoordinates(
  double latitude,
  double longitude, {
  String? localeIdentifier,
}) async {
  final rows = await _request({
    'lat': latitude.toString(),
    'lon': longitude.toString(),
  });
  return rows.map((row) {
    final a = row['address'] as Map<String, dynamic>? ?? {};
    return Placemark(
      name: row['name'] as String?,
      street: a['road'] as String?,
      thoroughfare: a['road'] as String?,
      subThoroughfare: a['house_number'] as String?,
      subLocality: (a['suburb'] ?? a['neighbourhood']) as String?,
      locality:
          (a['city'] ?? a['town'] ?? a['village'] ?? a['municipality'])
              as String?,
      subAdministrativeArea: a['county'] as String?,
      administrativeArea: a['state'] as String?,
      postalCode: a['postcode'] as String?,
      country: a['country'] as String?,
      isoCountryCode: (a['country_code'] as String?)?.toUpperCase(),
    );
  }).toList();
}

Future<List<Location>> locationFromAddress(
  String address, {
  String? localeIdentifier,
}) async {
  final rows = await _request({'q': address});
  return rows
      .map(
        (row) => Location(
          latitude: double.parse(row['lat'].toString()),
          longitude: double.parse(row['lon'].toString()),
          timestamp: DateTime.now(),
        ),
      )
      .toList();
}
