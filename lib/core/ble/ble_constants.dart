class BleConstants {
  // Default UUIDs (HM-10 style serial service FFE0 / characteristic FFE1)
  static const String defaultServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String defaultWriteCharacteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String defaultNotifyCharacteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
  
  /// No specific watch model by default — any compatible device works.
  static const String defaultPreferredDeviceName = '';

  /// Placeholder shown wherever a device name is needed but none is set.
  static const String genericDeviceLabel = 'Relógio';
  
  // Scan duration
  static const Duration scanDuration = Duration(seconds: 10);
  
  // Connection timeout
  static const Duration connectionTimeout = Duration(seconds: 15);
}

