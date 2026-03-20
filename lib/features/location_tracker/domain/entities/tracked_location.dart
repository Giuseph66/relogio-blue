class TrackedLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  TrackedLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TrackedLocation.fromJson(Map<String, dynamic> json) {
    return TrackedLocation(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num).toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
