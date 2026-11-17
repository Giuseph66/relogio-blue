import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/tracked_location.dart';
import '../../domain/entities/location_visit.dart';
import '../../domain/entities/location_question.dart';
import '../../data/repositories/location_tracker_repository.dart';
import '../../data/datasources/remote_location_data_source.dart';
import '../../../maps_old/domain/entities/map_location.dart';
import 'package:uuid/uuid.dart';

/// Outcome of [LocationTrackerController.syncFromServer].
class LocationSyncResult {
  /// Locations that did not exist locally.
  final int added;

  /// Locations whose data or questions changed on the server — their visit was
  /// cleared, so the question will be asked again on the next entry.
  final int updated;

  /// Locations returned by the server with no changes.
  final int unchanged;

  const LocationSyncResult({
    required this.added,
    required this.updated,
    required this.unchanged,
  });

  int get total => added + updated + unchanged;
}

class LocationTrackerController extends ChangeNotifier {
  final LocationTrackerRepository _repository;
  final Uuid _uuid = const Uuid();

  List<TrackedLocation> _locations = [];
  List<LocationVisit> _visits = [];

  /// When the user first entered this location's radius (key = locationId).
  final Map<String, DateTime> _dwellStartTimes = {};


  /// Minimum continuous time inside the radius before registering a visit.
  static const Duration dwellDuration = Duration(seconds: 10);


  List<TrackedLocation> get locations => List.unmodifiable(_locations);
  List<LocationVisit> get visits => List.unmodifiable(_visits);

  LocationTrackerController({required LocationTrackerRepository repository})
      : _repository = repository;

  Future<void> loadData() async {
    final locResult = await _repository.getLocations();
    if (locResult.isSuccess) {
      _locations = (locResult.valueOrNull ?? []).toList();
    }

    final visResult = await _repository.getVisits();
    if (visResult.isSuccess) {
      _visits = (visResult.valueOrNull ?? []).toList();
      _visits.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    notifyListeners();
  }

  Future<void> addLocation(String name, double lat, double lng,
      {double radiusMeters = 50.0}) async {
    final newLoc = TrackedLocation(
      id: _uuid.v4(),
      name: name,
      latitude: lat,
      longitude: lng,
      radiusMeters: radiusMeters,
      createdAt: DateTime.now(),
    );
    _locations.add(newLoc);
    await _repository.saveLocations(_locations);
    notifyListeners();
  }

  Future<void> removeLocation(String id) async {
    _locations.removeWhere((loc) => loc.id == id);
    _visits.removeWhere((visit) => visit.locationId == id);
    _dwellStartTimes.remove(id);
    await _repository.saveLocations(_locations);
    await _repository.saveVisits(_visits);
    notifyListeners();
  }

  /// Re-fetches every location (and its active questions) for the current
  /// city/position and merges it into the local catalog.
  ///
  /// Each server location gets a [TrackedLocation.revision] fingerprint built
  /// from its own data plus the questions that apply to it. When the
  /// fingerprint changes, the location is treated as new: its visits are
  /// cleared so the question is asked again on the next geofence entry.
  /// Throws on network/parse error.
  Future<LocationSyncResult> syncFromServer(
    String serverUrl, {
    required double latitude,
    required double longitude,
    String? city,
  }) async {
    final dataSource = RemoteLocationDataSource(baseUrl: serverUrl);
    final catalog = await dataSource.fetchCatalog(
      latitude: latitude,
      longitude: longitude,
      city: city,
    );

    var added = 0;
    var updated = 0;
    var unchanged = 0;
    var catalogChanged = false;
    final resetIds = <String>{};

    for (final serverLoc in catalog.locations) {
      final revision = _revisionFor(serverLoc, catalog.questions);
      final fresh = serverLoc.withRevision(revision);
      final index = _locations.indexWhere((l) => l.id == serverLoc.id);

      if (index == -1) {
        _locations.add(fresh);
        added++;
        catalogChanged = true;
        continue;
      }

      final previous = _locations[index];
      if (previous.revision == revision) {
        unchanged++;
        continue;
      }

      _locations[index] = fresh;
      catalogChanged = true;
      if (previous.revision == null) {
        // Synced before fingerprints existed: just record the baseline,
        // don't re-ask a question the user may have already answered.
        unchanged++;
      } else {
        updated++;
        resetIds.add(previous.id);
      }
    }

    if (resetIds.isNotEmpty) {
      _visits.removeWhere((v) => resetIds.contains(v.locationId));
      resetIds.forEach(_dwellStartTimes.remove);
      await _repository.saveVisits(_visits);
    }
    if (catalogChanged) {
      await _repository.saveLocations(_locations);
    }
    if (catalogChanged || resetIds.isNotEmpty) notifyListeners();

    return LocationSyncResult(
      added: added,
      updated: updated,
      unchanged: unchanged,
    );
  }

  /// Stable fingerprint (FNV-1a 64) of a location + the questions that apply
  /// to it (its own and the city-wide ones without locationId).
  String _revisionFor(TrackedLocation loc, List<LocationQuestion> questions) {
    final relevant = questions
        .where((q) => q.locationId == null || q.locationId == loc.id)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    final buffer = StringBuffer()
      ..write('L|${loc.name}|${loc.latitude}|${loc.longitude}|${loc.radiusMeters}');
    for (final q in relevant) {
      buffer.write('\nQ|${q.id}|${q.prompt}|${q.updatedAt ?? ''}');
      for (final o in q.options) {
        buffer.write('|${o.id}=${o.label}');
      }
    }

    if (kIsWeb) {
      var hash = BigInt.parse('cbf29ce484222325', radix: 16);
      final prime = BigInt.parse('100000001b3', radix: 16);
      final mask = (BigInt.one << 64) - BigInt.one;
      for (final unit in buffer.toString().codeUnits) {
        hash = ((hash ^ BigInt.from(unit)) * prime) & mask;
      }
      return hash.toRadixString(16);
    }
    var hash = int.parse('0xcbf29ce484222325');
    const prime = 0x100000001b3;
    for (final unit in buffer.toString().codeUnits) {
      hash ^= unit;
      hash = (hash * prime) & -1;
    }
    return hash.toUnsigned(64).toRadixString(16);
  }

  Future<void> clearVisits() async {
    _visits.clear();
    await _repository.saveVisits(_visits);
    notifyListeners();
  }

  /// Called by the map screen whenever the GPS position updates.
  ///
  /// Returns the [TrackedLocation] that triggered a new visit, or null if
  /// no visit was recorded this tick.
  Future<TrackedLocation?> checkProximityAndRegisterVisit(
      MapLocation currentLocation) async {
    if (_locations.isEmpty) return null;

    final now = DateTime.now();
    TrackedLocation? visitedLoc;

    for (final loc in _locations) {
      final distance = _calculateDistanceInMeters(
        currentLocation.latitude,
        currentLocation.longitude,
        loc.latitude,
        loc.longitude,
      );

      if (distance <= loc.radiusMeters) {
        // ─── Inside the geofence ─────────────────────────────────────────
        // Start dwell timer if this is the first tick inside.
        _dwellStartTimes.putIfAbsent(loc.id, () => now);

        final dwellElapsed = now.difference(_dwellStartTimes[loc.id]!);

        if (dwellElapsed >= dwellDuration) {
          // Only register if this location was never visited before.
          final alreadyVisited = _visits.any((v) => v.locationId == loc.id);
          if (!alreadyVisited) {
            final visit = LocationVisit(
              id: _uuid.v4(),
              locationId: loc.id,
              timestamp: now,
            );
            _visits.insert(0, visit);
            _dwellStartTimes.remove(loc.id);
            visitedLoc = loc;
          }
        }
      } else {
        // ─── Outside the geofence — reset dwell timer ────────────────────
        _dwellStartTimes.remove(loc.id);
      }
    }

    if (visitedLoc != null) {
      await _repository.saveVisits(_visits);
      notifyListeners();
      return visitedLoc;
    }

    return null;
  }

  /// Haversine formula: returns distance in metres.
  double _calculateDistanceInMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);

    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double degrees) => degrees * pi / 180;
}
