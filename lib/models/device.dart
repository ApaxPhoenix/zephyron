class Device {
  final int bus;
  final int address;
  final int vendor;
  final int type;
  final int classification;
  final int speed;
  final String manufacturer;
  final String product;
  final String serial;

  Device({
    required this.bus,
    required this.address,
    required this.vendor,
    required this.type,
    required this.classification,
    required this.speed,
    required this.manufacturer,
    required this.product,
    required this.serial,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      bus: json['bus'] ?? '',
      address: json['address'] ?? '',
      vendor: json['vendor'] ?? '',
      type: json['type'] ?? '',
      classification: json['classification'] ?? '',
      speed: json['speed'] ?? '',
      manufacturer: json['manufacturer'] ?? '',
      product: json['product'] ?? '',
      serial: json['serial'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bus': bus,
      'address': address,
      'vendor': vendor,
      'type': type,
      'classification': classification,
      'speed': speed,
      'manufacturer': manufacturer,
      'product': product,
      'serial': serial,
    };
  }

  Device copyWith({
    int? bus,
    int? address,
    int? vendor,
    int? type,
    int? classification,
    int? speed,
    String? manufacturer,
    String? product,
    String? serial,
  }) {
    return Device(
      bus: bus ?? this.bus,
      address: address ?? this.address,
      vendor: vendor ?? this.vendor,
      type: type ?? this.type,
      classification: classification ?? this.classification,
      speed: speed ?? this.speed,
      manufacturer: manufacturer ?? this.manufacturer,
      product: product ?? this.product,
      serial: serial ?? this.serial,
    );
  }
}
