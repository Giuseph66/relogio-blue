import '../../domain/entities/ble_settings.dart';
import '../../../../core/ble/ble_constants.dart';

/// Model for BLE Settings (extends entity)
class BleSettingsModel extends BleSettings {
  const BleSettingsModel({
    super.connectionMode,
    required super.serviceUuid,
    required super.writeCharacteristicUuid,
    required super.notifyCharacteristicUuid,
    super.preferredDeviceName,
    super.preferredDeviceId,
    super.autoReconnect,
    super.enableMockMode,
  });

  factory BleSettingsModel.defaults() {
    return BleSettingsModel(
      serviceUuid: BleConstants.defaultServiceUuid,
      writeCharacteristicUuid: BleConstants.defaultWriteCharacteristicUuid,
      notifyCharacteristicUuid: BleConstants.defaultNotifyCharacteristicUuid,
      preferredDeviceName: BleConstants.defaultPreferredDeviceName,
      autoReconnect: false,
      enableMockMode: false,
    );
  }

  factory BleSettingsModel.fromJson(Map<String, dynamic> json) {
    return BleSettingsModel(
      connectionMode: ConnectionMode.values.firstWhere(
        (e) => e.name == json['connectionMode'],
        orElse: () => ConnectionMode.ble,
      ),
      serviceUuid: json['serviceUuid'] as String? ?? BleConstants.defaultServiceUuid,
      writeCharacteristicUuid: json['writeCharacteristicUuid'] as String? ?? BleConstants.defaultWriteCharacteristicUuid,
      notifyCharacteristicUuid: json['notifyCharacteristicUuid'] as String? ?? BleConstants.defaultNotifyCharacteristicUuid,
      preferredDeviceName: json['preferredDeviceName'] as String? ?? '',
      preferredDeviceId: json['preferredDeviceId'] as String?,
      autoReconnect: json['autoReconnect'] as bool? ?? false,
      enableMockMode: json['enableMockMode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connectionMode': connectionMode.name,
      'serviceUuid': serviceUuid,
      'writeCharacteristicUuid': writeCharacteristicUuid,
      'notifyCharacteristicUuid': notifyCharacteristicUuid,
      'preferredDeviceName': preferredDeviceName,
      'preferredDeviceId': preferredDeviceId,
      'autoReconnect': autoReconnect,
      'enableMockMode': enableMockMode,
    };
  }

  @override
  BleSettingsModel copyWith({
    ConnectionMode? connectionMode,
    String? serviceUuid,
    String? writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
    String? preferredDeviceName,
    String? preferredDeviceId,
    bool? autoReconnect,
    bool? enableMockMode,
  }) {
    return BleSettingsModel(
      connectionMode: connectionMode ?? this.connectionMode,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      writeCharacteristicUuid: writeCharacteristicUuid ?? this.writeCharacteristicUuid,
      notifyCharacteristicUuid: notifyCharacteristicUuid ?? this.notifyCharacteristicUuid,
      preferredDeviceName: preferredDeviceName ?? this.preferredDeviceName,
      preferredDeviceId: preferredDeviceId ?? this.preferredDeviceId,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      enableMockMode: enableMockMode ?? this.enableMockMode,
    );
  }
}
