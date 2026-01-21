import '../entities/map_location.dart';

/// Repository contract for location services
abstract class LocationRepository {
  /// Get current position (latitude and longitude)
  /// Throws exception if permission denied or GPS disabled
  Future<MapLocation> getCurrentPosition();

  /// Convert coordinates to readable address
  /// Returns address string or null if geocoding fails
  Future<String?> reverseGeocode(double latitude, double longitude);

  /// Check if location permission is granted
  Future<bool> checkPermission();

  /// Request location permission
  Future<bool> requestPermission();

  /// Check if location service (GPS) is enabled
  Future<bool> isLocationServiceEnabled();
}

