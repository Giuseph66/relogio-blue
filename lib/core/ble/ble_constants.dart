class BleConstants {
  // Default UUIDs for ESP32
  static const String defaultServiceUuid = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const String defaultWriteCharacteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
  static const String defaultNotifyCharacteristicUuid = '0000ffe1-0000-1000-8000-00805f9b34fb';
  
  // Default device name
  static const String defaultPreferredDeviceName = 'ESP32';
  
  // Scan duration
  static const Duration scanDuration = Duration(seconds: 10);
  
  // Connection timeout
  static const Duration connectionTimeout = Duration(seconds: 15);
}

