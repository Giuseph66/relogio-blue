import '../entities/map_location.dart';
import '../repositories/location_repository.dart';

/// Use case to get current location
class GetCurrentLocation {
  final LocationRepository _repository;

  GetCurrentLocation(this._repository);

  /// Execute use case: get current position
  /// Returns MapLocation with latitude, longitude and timestamp
  /// Throws exception if permission denied or GPS disabled
  Future<MapLocation> call() async {
    return await _repository.getCurrentPosition();
  }
}

