import 'package:geolocator/geolocator.dart';
import '../../../../core/logger/app_logger.dart';

/// Data source for geolocation using geolocator package
class GeolocatorDataSource {
  /// Get current position
  Future<Position> getCurrentPosition({
    LocationAccuracy desiredAccuracy = LocationAccuracy.high,
  }) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
      );
      AppLogger.debug('Posição obtida: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      AppLogger.error('Erro ao obter posição atual', e);
      rethrow;
    }
  }

  /// Check location permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Check if location service is enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Open app settings
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Open location settings
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}

