/// Browsers have no Android foreground service. BLE stays in the UI session.
class BleForegroundServiceManager {
  Future<void> init() async {}
  Future<bool> ensureRunning() async => false;
  Future<bool> startBleKeepAliveService({
    required String deviceId,
    String? deviceName,
    required String serviceUuid,
    required String notifyCharacteristicUuid,
    String? serverApiUrl,
    bool keepServiceWhenAppClosed = true,
    bool backgroundNotifyOnRx = true,
    bool backgroundNotifyFilterEnabled = false,
    List<String> backgroundNotifyAllowedPatterns = const [],
  }) async => false;
  Future<void> stopBleKeepAliveService() async {}
  Future<void> updateNotification({String? title, String? text}) async {}
  bool isRunning() => false;
  String? getCurrentDeviceId() => null;
  String? getCurrentDeviceName() => null;
  Future<bool> sendCommand(String command) async => false;
}
