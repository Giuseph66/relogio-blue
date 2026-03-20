import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/tracked_location.dart';
import '../../domain/entities/location_visit.dart';
import '../../data/repositories/location_tracker_repository.dart';
import '../../data/datasources/remote_location_data_source.dart';
import '../../../maps_old/domain/entities/map_location.dart';
import 'package:uuid/uuid.dart';

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

  /// Fetches locations from the server filtered by current position and merges
  /// with the local catalog. Returns the number of new locations added.
  /// Throws on network/parse error.
  Future<int> syncFromServer(
    String serverUrl, {
    required double latitude,
    required double longitude,
    String? city,
  }) async {
    final dataSource = RemoteLocationDataSource(baseUrl: serverUrl);
    final serverLocations = await dataSource.fetchLocations(
      latitude: latitude,
      longitude: longitude,
      city: city,
    );

    final existingIds = _locations.map((l) => l.id).toSet();
    final newLocations = serverLocations.where((l) => !existingIds.contains(l.id)).toList();

    if (newLocations.isNotEmpty) {
      _locations.addAll(newLocations);
      await _repository.saveLocations(_locations);
      notifyListeners();
    }

    return newLocations.length;
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
