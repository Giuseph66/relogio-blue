class BrowserBridge {
  static bool get bluetoothSupported => false;
  static bool get updateAvailable => false;
  static bool get isVisible => true;
  static bool get isStandalone => false;
  static Stream<Map<String, dynamic>> get events => const Stream.empty();
  static Future<dynamic> call(
    String method, [
    Map<String, dynamic> data = const {},
  ]) => Future.error(UnsupportedError('Recurso exclusivo do navegador'));
}
