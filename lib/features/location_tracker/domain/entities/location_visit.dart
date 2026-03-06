class LocationVisit {
  final String id;
  final String locationId;
  final DateTime timestamp;

  LocationVisit({
    required this.id,
    required this.locationId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'locationId': locationId,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory LocationVisit.fromJson(Map<String, dynamic> json) {
    return LocationVisit(
      id: json['id'],
      locationId: json['locationId'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
