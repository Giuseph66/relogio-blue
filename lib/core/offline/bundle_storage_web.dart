import '../platform/browser_bridge.dart';

class BundleStorage {
  Future<String?> read() async {
    final row = await BrowserBridge.call('db.get', {
      'store': 'cache',
      'id': 'offline_bundle',
    });
    return row == null ? null : row['value'] as String;
  }

  Future<void> write(String value) async {
    await BrowserBridge.call('db.put', {
      'store': 'cache',
      'value': {'id': 'offline_bundle', 'value': value},
    });
  }
}
