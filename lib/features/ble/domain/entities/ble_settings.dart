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
  final bool keepBleAliveInBackground;
  final bool backgroundNotifyOnRx;
  final String? backgroundServiceTitle;
  final String? backgroundServiceText;
  final String serverApiUrl;

  const BleSettings({
    this.connectionMode = ConnectionMode.ble,
    required this.serviceUuid,
    required this.writeCharacteristicUuid,
    required this.notifyCharacteristicUuid,
    this.preferredDeviceName = '',
    this.preferredDeviceId,
    this.autoReconnect = false,
    this.enableMockMode = false,
    this.keepBleAliveInBackground = true,
    this.backgroundNotifyOnRx = true,
    this.backgroundServiceTitle,
    this.backgroundServiceText,
    this.serverApiUrl = '',
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
    bool? keepBleAliveInBackground,
    bool? backgroundNotifyOnRx,
    String? backgroundServiceTitle,
    String? backgroundServiceText,
    String? serverApiUrl,
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
      keepBleAliveInBackground: keepBleAliveInBackground ?? this.keepBleAliveInBackground,
      backgroundNotifyOnRx: backgroundNotifyOnRx ?? this.backgroundNotifyOnRx,
      backgroundServiceTitle: backgroundServiceTitle ?? this.backgroundServiceTitle,
      backgroundServiceText: backgroundServiceText ?? this.backgroundServiceText,
      serverApiUrl: serverApiUrl ?? this.serverApiUrl,
    );
  }

  bool get isValid {
    return serviceUuid.isNotEmpty &&
        writeCharacteristicUuid.isNotEmpty &&
        notifyCharacteristicUuid.isNotEmpty;
  }
}
