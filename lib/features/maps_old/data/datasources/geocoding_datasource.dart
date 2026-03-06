import 'package:geocoding/geocoding.dart' as geocoding;
import '../../../../core/logger/app_logger.dart';

/// Data source for geocoding using geocoding package
class GeocodingDataSource {
  /// Convert coordinates to placemark (address)
  Future<List<geocoding.Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        latitude,
        longitude,
      );
      AppLogger.debug('Placemarks obtidos: ${placemarks.length}');
      return placemarks;
    } catch (e) {
      AppLogger.error('Erro ao fazer reverse geocoding', e);
      rethrow;
    }
  }

  /// Format placemark to readable address string
  String formatAddress(geocoding.Placemark placemark) {
    final parts = <String>[];
    
    if (placemark.street != null && placemark.street!.isNotEmpty) {
      parts.add(placemark.street!);
    }
    if (placemark.subThoroughfare != null && placemark.subThoroughfare!.isNotEmpty) {
      parts.insert(0, placemark.subThoroughfare!);
    }
    if (placemark.thoroughfare != null && placemark.thoroughfare!.isNotEmpty) {
      if (parts.isEmpty || !parts.first.contains(placemark.thoroughfare!)) {
        parts.insert(0, placemark.thoroughfare!);
      }
    }
    if (placemark.subLocality != null && placemark.subLocality!.isNotEmpty) {
      parts.add(placemark.subLocality!);
    }
    if (placemark.locality != null && placemark.locality!.isNotEmpty) {
      parts.add(placemark.locality!);
    }
    if (placemark.subAdministrativeArea != null && placemark.subAdministrativeArea!.isNotEmpty) {
      parts.add(placemark.subAdministrativeArea!);
    }
    if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
      parts.add(placemark.administrativeArea!);
    }
    if (placemark.postalCode != null && placemark.postalCode!.isNotEmpty) {
      parts.add(placemark.postalCode!);
    }
    if (placemark.country != null && placemark.country!.isNotEmpty) {
      parts.add(placemark.country!);
    }

    return parts.join(', ');
  }
}

