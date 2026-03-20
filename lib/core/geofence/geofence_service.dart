import 'dart:async';

import 'package:geocoding/geocoding.dart' as geocoding;

import '../logger/app_logger.dart';
import '../../features/maps_old/domain/entities/map_location.dart';
import '../../features/maps_old/domain/usecases/get_current_location.dart';
import '../../features/location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../features/location_tracker/presentation/controllers/visit_question_orchestrator.dart';

/// Singleton background-aware service that polls GPS every [pollInterval] and
/// triggers geofence detection + the question flow independently of any page
/// being open.
///
/// The service must be [start]ed after all dependencies are initialized.
/// Call [updateLocation] from the map page so the UI and geofence share state.
class GeofenceService {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  static const Duration pollInterval = Duration(seconds: 10);

  late final GetCurrentLocation _getLocation;
  late final LocationTrackerController _tracker;
  late final VisitQuestionOrchestrator _orchestrator;

  Timer? _timer;
  String? _lastCity;
  bool _running = false;

  void init({
    required GetCurrentLocation getLocation,
    required LocationTrackerController tracker,
    required VisitQuestionOrchestrator orchestrator,
  }) {
    _getLocation = getLocation;
    _tracker = tracker;
    _orchestrator = orchestrator;
  }

  /// Start GPS polling. Safe to call multiple times.
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    AppLogger.info('GeofenceService: started (interval=${pollInterval.inSeconds}s)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    AppLogger.info('GeofenceService: stopped');
  }

  bool get isRunning => _running;

  /// Called from the map page when it receives a GPS update, so both the UI
  /// and the geofence service share the same position + city without doubling
  /// the GPS requests.
  void updateLocation(MapLocation location, {String? city}) {
    if (city != null) _lastCity = city;
    // Run geofence check immediately on each UI-driven update.
    _checkGeofence(location);
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _tick() async {
    try {
      final location = await _getLocation();
      // Reverse geocode lazily (only when city is stale / first tick).
      if (_lastCity == null) {
        _lastCity = await _resolveCity(location.latitude, location.longitude);
      }
      _checkGeofence(location);
    } catch (e) {
      AppLogger.debug('GeofenceService: tick error: $e');
    }
  }

  void _checkGeofence(MapLocation location) async {
    final visited = await _tracker.checkProximityAndRegisterVisit(location);
    if (visited != null) {
      AppLogger.info('GeofenceService: visit detected – ${visited.name}');
      _orchestrator.handleVisit(
        visited,
        latitude: location.latitude,
        longitude: location.longitude,
        city: _lastCity,
      );
    }
  }

  Future<String?> _resolveCity(double lat, double lng) async {
    try {
      final marks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final p = marks.first;
      return (p.locality?.isNotEmpty == true)
          ? p.locality
          : (p.subAdministrativeArea?.isNotEmpty == true)
              ? p.subAdministrativeArea
              : p.administrativeArea;
    } catch (_) {
      return null;
    }
  }
}
