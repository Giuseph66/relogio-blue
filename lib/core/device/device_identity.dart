import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_service.dart';
import '../logger/app_logger.dart';
import '../platform/browser_bridge.dart';

/// Identifies this phone so the server accepts one answer per question.
///
/// Android hides the MAC address from apps, so this is a hash of ANDROID_ID:
/// it survives clearing the app's data and reinstalling it. In the browser the
/// server identifies the device by itself, with an HttpOnly cookie.
class DeviceIdentity {
  static const _channel = MethodChannel('geonexo/device');
  static const _key = 'device_identity';

  /// Reads the identity again on every start. Only the UI isolate has the
  /// channel; background isolates use the value stored here.
  static Future<void> init() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id;
      if (defaultTargetPlatform == TargetPlatform.android) {
        id = await _channel.invokeMethod<String>('deviceId');
        if (id == null) {
          AppLogger.warning('DeviceIdentity: ANDROID_ID unavailable');
        }
      }
      id ??= prefs.getString(_key) ?? 'app-${const Uuid().v4()}';
      await prefs.setString(_key, id);
    } catch (error) {
      // Answers stay pending on the phone until it can be read.
      AppLogger.error('DeviceIdentity: unavailable', error);
    }
  }

  /// Answers are accepted from the APK and the installed PWA, not from a
  /// browser tab. Administrators are exempt.
  static bool get canAnswer => answerAllowed(
        web: kIsWeb,
        standalone: BrowserBridge.isStandalone,
        admin: AuthService().isAuthenticated,
      );

  @visibleForTesting
  static bool answerAllowed({
    required bool web,
    required bool standalone,
    required bool admin,
  }) =>
      !web || standalone || admin;

  /// Null in the browser, or when [init] has not succeeded yet.
  static Future<String?> read() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(_key);
  }
}
