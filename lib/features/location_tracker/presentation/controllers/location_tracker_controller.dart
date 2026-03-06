import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../domain/entities/tracked_location.dart';
import '../../domain/entities/location_visit.dart';
import '../../data/repositories/location_tracker_repository.dart';
import '../../../maps_old/domain/entities/map_location.dart';
import 'package:uuid/uuid.dart';

class LocationTrackerController extends ChangeNotifier {
  final LocationTrackerRepository _repository;
  final Uuid _uuid = const Uuid();

  List<TrackedLocation> _locations = [];
  List<LocationVisit> _visits = [];
  final Map<String, DateTime> _lastVisitTimes = {};

  // O tempo mínimo entre registros de visita para o mesmo local (cooldown).
  static const Duration _cooldownDuration = Duration(minutes: 5);

  List<TrackedLocation> get locations => List.unmodifiable(_locations);
  List<LocationVisit> get visits => List.unmodifiable(_visits);

  LocationTrackerController({required LocationTrackerRepository repository})
      : _repository = repository;

  Future<void> loadData() async {
    final locResult = await _repository.getLocations();
    if (locResult.isSuccess) {
      // .toList() creates a mutable copy — const [] from Success([]) is unmodifiable
      _locations = (locResult.valueOrNull ?? []).toList();
    }

    final visResult = await _repository.getVisits();
    if (visResult.isSuccess) {
      // .toList() creates a mutable copy before sorting
      _visits = (visResult.valueOrNull ?? []).toList();
      _visits.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    notifyListeners();
  }

  Future<void> addLocation(String name, double lat, double lng, {double radiusMeters = 50.0}) async {
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
    await _repository.saveLocations(_locations);
    await _repository.saveVisits(_visits);
    notifyListeners();
  }

  Future<void> clearVisits() async {
    _visits.clear();
    _lastVisitTimes.clear();
    await _repository.saveVisits(_visits);
    notifyListeners();
  }

  /// Chamado pela tela do mapa quando há uma atualização de GPS
  Future<TrackedLocation?> checkProximityAndRegisterVisit(MapLocation currentLocation) async {
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
        // Verifica o cooldown
        final lastVisitTime = _lastVisitTimes[loc.id];
        if (lastVisitTime == null || now.difference(lastVisitTime) > _cooldownDuration) {
          // Registrar nova visita
          final visit = LocationVisit(
            id: _uuid.v4(),
            locationId: loc.id,
            timestamp: now,
          );
          _visits.insert(0, visit); // Mantém no topo (mais recente)
          _lastVisitTimes[loc.id] = now;
          visitedLoc = loc; // Retorna para possibilitar disparar um snackbar na UI
        }
      }
    }

    if (visitedLoc != null) {
      await _repository.saveVisits(_visits);
      notifyListeners();
      return visitedLoc;
    }

    return null;
  }

  /// Fórmula de Haversine para calcular distância entre coordenadas
  double _calculateDistanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // Raio da Terra em metros
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}
