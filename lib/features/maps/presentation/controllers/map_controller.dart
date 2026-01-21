import 'dart:async';
import '../../../../core/logger/app_logger.dart';
import '../../domain/entities/map_location.dart';
import '../../domain/usecases/get_current_location.dart';
import '../../domain/usecases/reverse_geocode.dart';
import '../../domain/repositories/location_repository.dart';

/// Controller for map functionality
class MapController {
  final GetCurrentLocation _getCurrentLocation;
  final ReverseGeocode _reverseGeocode;
  final LocationRepository _locationRepository;

  // State streams
  final _isLoadingController = StreamController<bool>.broadcast();
  final _locationController = StreamController<MapLocation?>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _permissionGrantedController = StreamController<bool>.broadcast();
  final _serviceEnabledController = StreamController<bool>.broadcast();

  Stream<bool> get isLoading => _isLoadingController.stream;
  Stream<MapLocation?> get location => _locationController.stream;
  Stream<String?> get error => _errorController.stream;
  Stream<bool> get permissionGranted => _permissionGrantedController.stream;
  Stream<bool> get serviceEnabled => _serviceEnabledController.stream;

  bool _isLoading = false;
  MapLocation? _currentLocation;
  String? _error;
  bool _permissionGranted = false;
  bool _serviceEnabled = false;

  MapController(
    this._getCurrentLocation,
    this._reverseGeocode,
    this._locationRepository,
  ) {
    _initialize();
  }

  /// Initialize controller - check permissions and service status
  Future<void> _initialize() async {
    try {
      _serviceEnabled = await _locationRepository.isLocationServiceEnabled();
      _serviceEnabledController.add(_serviceEnabled);

      _permissionGranted = await _locationRepository.checkPermission();
      _permissionGrantedController.add(_permissionGranted);
    } catch (e) {
      AppLogger.error('Erro ao inicializar MapController', e);
    }
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    try {
      _permissionGranted = await _locationRepository.requestPermission();
      _permissionGrantedController.add(_permissionGranted);
      return _permissionGranted;
    } catch (e) {
      AppLogger.error('Erro ao solicitar permissão', e);
      return false;
    }
  }

  /// Fetch current location - complete flow
  Future<void> fetchMyLocation() async {
    if (_isLoading) return;

    try {
      _isLoading = true;
      _isLoadingController.add(true);
      _error = null;
      _errorController.add(null);

      // Check service enabled
      _serviceEnabled = await _locationRepository.isLocationServiceEnabled();
      _serviceEnabledController.add(_serviceEnabled);

      if (!_serviceEnabled) {
        _error = 'GPS_DISABLED';
        _errorController.add(_error);
        _isLoading = false;
        _isLoadingController.add(false);
        return;
      }

      // Check permission
      _permissionGranted = await _locationRepository.checkPermission();
      _permissionGrantedController.add(_permissionGranted);

      if (!_permissionGranted) {
        final granted = await requestPermission();
        if (!granted) {
          _error = 'PERMISSION_DENIED';
          _errorController.add(_error);
          _isLoading = false;
          _isLoadingController.add(false);
          return;
        }
      }

      // Get current position
      final location = await _getCurrentLocation();
      
      // Try to get address
      String? address;
      try {
        address = await _reverseGeocode.call(location.latitude, location.longitude);
      } catch (e) {
        AppLogger.warning('Erro ao obter endereço, continuando sem ele: $e');
        // Continue without address
      }

      // Update location with address
      _currentLocation = location.copyWith(address: address);
      _locationController.add(_currentLocation);

      _isLoading = false;
      _isLoadingController.add(false);
    } catch (e) {
      AppLogger.error('Erro ao buscar localização', e);
      _error = 'FETCH_ERROR';
      _errorController.add(_error);
      _isLoading = false;
      _isLoadingController.add(false);
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    _errorController.add(null);
  }


  /// Get current location (if available)
  MapLocation? get currentLocation => _currentLocation;

  /// Dispose resources
  void dispose() {
    _isLoadingController.close();
    _locationController.close();
    _errorController.close();
    _permissionGrantedController.close();
    _serviceEnabledController.close();
  }
}

