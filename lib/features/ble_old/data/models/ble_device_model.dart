import '../../domain/entities/ble_device.dart';

/// Model for BLE Device (extends entity)
class BleDeviceModel extends BleDevice {
  const BleDeviceModel({
    required super.id,
    required super.name,
    super.rssi,
    super.isPreferred,
  });

  factory BleDeviceModel.fromJson(Map<String, dynamic> json) {
    return BleDeviceModel(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      rssi: json['rssi'] as int?,
      isPreferred: json['isPreferred'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'rssi': rssi,
      'isPreferred': isPreferred,
    };
  }
}

