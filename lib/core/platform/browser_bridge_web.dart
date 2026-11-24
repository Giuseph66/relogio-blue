import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('geonexo.call')
external JSPromise<JSString> _call(String method, String data);
@JS('geonexo.listen')
external void _listen(JSFunction callback);
@JS('geonexo.bluetoothSupported')
external bool get _bluetoothSupported;
@JS('geonexo.updateAvailable')
external bool get _updateAvailable;
@JS('geonexo.isStandalone')
external bool get _isStandalone;
@JS('geonexo.isVisible')
external bool get _isVisible;

class BrowserBridge {
  static final _events = StreamController<Map<String, dynamic>>.broadcast();
  static bool _listening = false;
  static bool get bluetoothSupported => _bluetoothSupported;
  static bool get updateAvailable => _updateAvailable;
  static bool get isVisible => _isVisible;
  static bool get isStandalone => _isStandalone;

  static Stream<Map<String, dynamic>> get events {
    if (!_listening) {
      _listening = true;
      _listen(
        ((String raw) {
          _events.add(jsonDecode(raw) as Map<String, dynamic>);
        }).toJS,
      );
    }
    return _events.stream;
  }

  static Future<dynamic> call(
    String method, [
    Map<String, dynamic> data = const {},
  ]) {
    // Invoke synchronously: requestDevice must retain the button's user gesture.
    final promise = _call(method, jsonEncode(data));
    return promise.toDart.then((value) {
      final result = jsonDecode(value.toDart) as Map<String, dynamic>;
      if (result['ok'] != true) throw StateError(result['error'] as String);
      return result['value'];
    });
  }
}
