import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/location_tracker/domain/entities/location_question.dart';
import '../config/app_config.dart';
import '../logger/app_logger.dart';

/// Location as stored in the offline bundle.
class CachedLocation {
  final String id;
  final String name;
  final String? city;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const CachedLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.city,
  });

  factory CachedLocation.fromJson(Map<String, dynamic> json) {
    return CachedLocation(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      city: json['city'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 100,
    );
  }

  double distanceTo(double lat, double lng) =>
      haversineMeters(lat, lng, latitude, longitude);
}

class _CachedQuestion {
  final LocationQuestion question;
  final String? city;
  final DateTime? validFrom;
  final DateTime? validUntil;

  const _CachedQuestion(this.question, this.city, this.validFrom, this.validUntil);

  bool isValidAt(DateTime now) =>
      (validFrom == null || !validFrom!.isAfter(now)) &&
      (validUntil == null || !validUntil!.isBefore(now));
}

/// Locations + questions mirrored from the server so visits can be detected
/// and questions asked without network. Stored as a JSON file next to the
/// SQLite database, so every isolate (UI, foreground service, notification
/// actions) reads the same data.
class OfflineQuestionCache {
  static final OfflineQuestionCache _instance = OfflineQuestionCache._internal();
  factory OfflineQuestionCache() => _instance;
  OfflineQuestionCache._internal();

  static const String _fileName = 'offline_bundle.json';

  List<CachedLocation> _locations = const [];
  List<_CachedQuestion> _questions = const [];
  DateTime? _fetchedAt;
  DateTime? _fileStamp;

  DateTime? get fetchedAt => _fetchedAt;

  Future<File> _file() async =>
      File(p.join(await getDatabasesPath(), _fileName));

  /// Downloads the bundle from the server. Returns false when offline/failed
  /// (the previous cache stays untouched).
  Future<bool> refresh({String baseUrl = AppConfig.serverApiUrl}) async {
    try {
      final uri = Uri.parse('${_normalize(baseUrl)}/api/location/offline-bundle');
      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${AppConfig.appAuthToken}',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        AppLogger.warning('OfflineCache: HTTP ${response.statusCode}');
        return false;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final stored = <String, dynamic>{
        'fetchedAt': DateTime.now().toIso8601String(),
        'locations': decoded['locations'] ?? const [],
        'questions': decoded['questions'] ?? const [],
      };

      // Write atomically so another isolate never reads a half-written file.
      final file = await _file();
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(stored), flush: true);
      await tmp.rename(file.path);

      _apply(stored);
      _fileStamp = await file.lastModified();
      AppLogger.info(
        'OfflineCache: refreshed (${_locations.length} locais, ${_questions.length} perguntas)',
      );
      return true;
    } catch (e) {
      AppLogger.debug('OfflineCache: refresh failed: $e');
      return false;
    }
  }

  /// Refreshes only if the cache is older than [maxAge] (or missing).
  Future<bool> refreshIfStale(Duration maxAge) async {
    await load();
    final fetched = _fetchedAt;
    if (fetched != null && DateTime.now().difference(fetched) < maxAge) {
      return true;
    }
    return refresh();
  }

  /// Loads the file into memory, re-reading it when another isolate updated it.
  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final stamp = await file.lastModified();
      if (_fileStamp != null && !stamp.isAfter(_fileStamp!)) return;
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _apply(decoded);
      _fileStamp = stamp;
    } catch (e) {
      AppLogger.warning('OfflineCache: load failed: $e');
    }
  }

  /// Cached locations whose geofence contains the point, nearest first.
  Future<List<CachedLocation>> locationsAt(double lat, double lng) async {
    await load();
    final inside = _locations
        .where((l) => l.distanceTo(lat, lng) <= l.radiusMeters)
        .toList()
      ..sort((a, b) => a.distanceTo(lat, lng).compareTo(b.distanceTo(lat, lng)));
    return inside;
  }

  /// Picks the question for [locationId] with the same rules as the server's
  /// resolve + the app's selection: questions of the matched locations, or
  /// location-less ones that are global / of [city]; prefer [locationId]'s own.
  Future<LocationQuestion?> questionFor({
    required String locationId,
    List<String>? matchedLocationIds,
    String? city,
  }) async {
    await load();
    final now = DateTime.now();
    final matched = {locationId, ...?matchedLocationIds};
    final normalizedCity = _normalizeCity(city);

    final eligible = _questions.where((q) {
      if (!q.isValidAt(now) || q.question.options.length < 2) return false;
      final locId = q.question.locationId;
      if (locId != null) return matched.contains(locId);
      final qCity = _normalizeCity(q.city);
      return qCity == null || (normalizedCity != null && qCity == normalizedCity);
    }).toList();

    if (eligible.isEmpty) return null;
    return eligible
        .firstWhere(
          (q) => q.question.locationId == locationId,
          orElse: () => eligible.first,
        )
        .question;
  }

  void _apply(Map<String, dynamic> data) {
    _fetchedAt = DateTime.tryParse(data['fetchedAt'] as String? ?? '');
    _locations = ((data['locations'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CachedLocation.fromJson)
        .toList(growable: false);
    _questions = ((data['questions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (j) => _CachedQuestion(
            LocationQuestion.fromJson(j),
            j['city'] as String?,
            DateTime.tryParse(j['validFrom'] as String? ?? ''),
            DateTime.tryParse(j['validUntil'] as String? ?? ''),
          ),
        )
        .toList(growable: false);
  }

  static String _normalize(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
  }

  static String? _normalizeCity(String? city) {
    final value = city?.trim().toLowerCase();
    return (value == null || value.isEmpty) ? null : value;
  }
}

double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
