/// BLE Settings entity
enum ConnectionMode {
  ble,
  wifi, // Future use
}

class BleSettings {
  final ConnectionMode connectionMode;
  final String serviceUuid;
  final String writeCharacteristicUuid;
  final String notifyCharacteristicUuid;
  final String preferredDeviceName;
  final String? preferredDeviceId;
  final bool autoReconnect;
  final bool enableMockMode;

  const BleSettings({
    this.connectionMode = ConnectionMode.ble,
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
    this.preferredDeviceName = '',
    this.preferredDeviceId,
    this.autoReconnect = false,
    this.enableMockMode = false,
  });

  BleSettings copyWith({
    ConnectionMode? connectionMode,
    String? serviceUuid,
    String? writeCharacteristicUuid,
    String? notifyCharacteristicUuid,
    String? preferredDeviceName,
    String? preferredDeviceId,
    bool? autoReconnect,
    bool? enableMockMode,
  }) {
    return BleSettings(
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

  bool get isValid {
    return serviceUuid.isNotEmpty &&
        writeCharacteristicUuid.isNotEmpty &&
        notifyCharacteristicUuid.isNotEmpty;
  }
}
