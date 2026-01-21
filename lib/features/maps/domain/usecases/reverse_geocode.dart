import '../repositories/location_repository.dart';

/// Use case to reverse geocode coordinates to address
class ReverseGeocode {
  final LocationRepository _repository;

  ReverseGeocode(this._repository);

  /// Execute use case: convert coordinates to address
  /// Returns address string or null if geocoding fails
  Future<String?> call(double latitude, double longitude) async {
    return await _repository.reverseGeocode(latitude, longitude);
  }
}

