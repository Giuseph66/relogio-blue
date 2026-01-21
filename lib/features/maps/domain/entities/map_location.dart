/// Entity representing a map location with coordinates and address
class MapLocation {
  final double latitude;
  final double longitude;
  final String? address;
  final DateTime timestamp;

  const MapLocation({
    required this.latitude,
    required this.longitude,
    this.address,
    required this.timestamp,
  });

  MapLocation copyWith({
    double? latitude,
    double? longitude,
    String? address,
    DateTime? timestamp,
  }) {
    return MapLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  String toString() {
    return 'MapLocation(lat: $latitude, lng: $longitude, address: $address, timestamp: $timestamp)';
  }
}

