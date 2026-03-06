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
  final bool keepServiceWhenAppClosed;
  final bool keepBleAliveInBackground;
  final bool backgroundNotifyOnRx;
  final bool backgroundNotifyFilterEnabled;
  final List<String> backgroundNotifyAllowedPatterns;
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
    this.keepServiceWhenAppClosed = true,
    this.keepBleAliveInBackground = true,
    this.backgroundNotifyOnRx = true,
    this.backgroundNotifyFilterEnabled = false,
    this.backgroundNotifyAllowedPatterns = const [],
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
    bool? keepServiceWhenAppClosed,
    bool? keepBleAliveInBackground,
    bool? backgroundNotifyOnRx,
    bool? backgroundNotifyFilterEnabled,
    List<String>? backgroundNotifyAllowedPatterns,
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
      keepServiceWhenAppClosed:
          keepServiceWhenAppClosed ?? this.keepServiceWhenAppClosed,
      keepBleAliveInBackground: keepBleAliveInBackground ?? this.keepBleAliveInBackground,
      backgroundNotifyOnRx: backgroundNotifyOnRx ?? this.backgroundNotifyOnRx,
      backgroundNotifyFilterEnabled:
          backgroundNotifyFilterEnabled ?? this.backgroundNotifyFilterEnabled,
      backgroundNotifyAllowedPatterns:
          backgroundNotifyAllowedPatterns ?? this.backgroundNotifyAllowedPatterns,
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
