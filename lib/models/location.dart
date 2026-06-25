class Location {
  final int id;
  final String ascii;
  final String iso;
  final double latitude;
  final double longitude;

  const Location({
    required this.id,
    required this.ascii,
    required this.iso,
    this.latitude = 0.0,
    this.longitude = 0.0,
  });

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      id: json['id'] as int? ?? 0,
      ascii: json['ascii'] as String? ?? '',
      iso: json['iso'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ascii': ascii,
    'iso': iso,
    'latitude': latitude,
    'longitude': longitude,
  };

  Location copyWith({
    int? id,
    String? ascii,
    String? iso,
    double? latitude,
    double? longitude,
  }) {
    return Location(
      id: id ?? this.id,
      ascii: ascii ?? this.ascii,
      iso: iso ?? this.iso,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }
}