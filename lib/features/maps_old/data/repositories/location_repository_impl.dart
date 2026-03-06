import 'package:geolocator/geolocator.dart';
import '../../../../core/logger/app_logger.dart';
import '../../domain/entities/map_location.dart';
import '../../domain/repositories/location_repository.dart';
import '../datasources/geolocator_datasource.dart';
import '../datasources/geocoding_datasource.dart';

/// Implementation of LocationRepository
class LocationRepositoryImpl implements LocationRepository {
  final GeolocatorDataSource _geolocatorDataSource;
  final GeocodingDataSource _geocodingDataSource;

  LocationRepositoryImpl(
    this._geolocatorDataSource,
    this._geocodingDataSource,
  );

  @override
  Future<MapLocation> getCurrentPosition() async {
    try {
      final position = await _geolocatorDataSource.getCurrentPosition();
      return MapLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      AppLogger.error('Erro ao obter posição atual', e);
      rethrow;
    }
  }

  @override
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await _geocodingDataSource.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      
      if (placemarks.isEmpty) {
        return null;
      }

      final placemark = placemarks.first;
      final address = _geocodingDataSource.formatAddress(placemark);
      return address.isEmpty ? null : address;
    } catch (e) {
      AppLogger.error('Erro ao fazer reverse geocoding', e);
      return null; // Retorna null em caso de erro, não lança exceção
    }
  }

  @override
  Future<bool> checkPermission() async {
    final permission = await _geolocatorDataSource.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<bool> requestPermission() async {
    final permission = await _geolocatorDataSource.requestPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  @override
  Future<bool> isLocationServiceEnabled() async {
    return await _geolocatorDataSource.isLocationServiceEnabled();
  }
}

