import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

import '../location/app_geocoding.dart' as geocoding;

import '../logger/app_logger.dart';
import '../../features/maps_old/domain/entities/map_location.dart';
import '../../features/maps_old/domain/usecases/get_current_location.dart';
import '../../features/location_tracker/presentation/controllers/location_tracker_controller.dart';
import '../../features/location_tracker/presentation/controllers/visit_question_orchestrator.dart';

enum GpsMonitoringStatus { stopped, locating, active, unavailable }

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
  bool _polling = false;
  bool _resolvingCity = false;
  DateTime? _catalogAttempt;
  final status = ValueNotifier(GpsMonitoringStatus.stopped);

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
  void start({bool pollImmediately = false}) {
    if (_running) return;
    _running = true;
    status.value = GpsMonitoringStatus.locating;
    if (kIsWeb) _catalogAttempt = null;
    if (pollImmediately) unawaited(_tick());
    _timer = Timer.periodic(pollInterval, (_) => _tick());
    AppLogger.info(
      'GeofenceService: started (interval=${pollInterval.inSeconds}s)',
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    status.value = GpsMonitoringStatus.stopped;
    AppLogger.info('GeofenceService: stopped');
  }

  bool get isRunning => _running;

  /// Called from the map page when it receives a GPS update, so both the UI
  /// and the geofence service share the same position + city without doubling
  /// the GPS requests.
  void updateLocation(MapLocation location, {String? city}) {
    if (kIsWeb && !_running) return;
    if (city != null) _lastCity = city;
    // Run geofence check immediately on each UI-driven update.
    unawaited(_checkGeofence(location));
  }

  // ─── Internal ─────────────────────────────────────────────────────────────

  Future<void> _tick() async {
    if (_polling) return;
    _polling = true;
    try {
      final location = kIsWeb
          ? await _getLocation().timeout(const Duration(seconds: 15))
          : await _getLocation();
      if (!_running) return;
      status.value = GpsMonitoringStatus.active;
      // A slow/offline address lookup must not delay visit detection.
      await _checkGeofence(location);
      if (kIsWeb &&
          (_catalogAttempt == null ||
              DateTime.now().difference(_catalogAttempt!) >=
                  const Duration(minutes: 2))) {
        _catalogAttempt = DateTime.now();
        try {
          await _tracker.syncFromServer(
            AppConfig.serverApiUrl,
            latitude: location.latitude,
            longitude: location.longitude,
            city: _lastCity,
          );
          if (_running) await _checkGeofence(location);
        } catch (error) {
          // Cached locations remain usable without the server.
          _catalogAttempt = DateTime.now().subtract(
            const Duration(seconds: 90),
          );
          AppLogger.debug('GeofenceService: catalog unavailable: $error');
        }
      }
      // Reverse geocode lazily (only when city is stale / first tick).
      if (_lastCity == null && !_resolvingCity) {
        _resolvingCity = true;
        unawaited(
          _resolveCity(location.latitude, location.longitude)
              .then((city) {
                _lastCity = city;
              })
              .whenComplete(() => _resolvingCity = false),
        );
      }
    } catch (e) {
      if (_running) status.value = GpsMonitoringStatus.unavailable;
      AppLogger.debug('GeofenceService: tick error: $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _checkGeofence(MapLocation location) async {
    final visited = await _tracker.checkProximityAndRegisterVisit(location);
    if (visited != null) {
      AppLogger.info('GeofenceService: visit detected – ${visited.name}');
      await _orchestrator.handleVisit(
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
