import '../platform/browser_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple hardcoded authentication service with persistence.
///
/// Credentials: admin@gmail.com / admin123
///
/// Usage:
///   await AuthService().init()          → restore session on app start
///   AuthService().login(email, password) → bool
///   AuthService().logout()
///   AuthService().isAuthenticated → bool
///   AuthService().isAuthenticatedNotifier → ValueNotifier<bool>  (for reactive UI)
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _email = 'admin@gmail.com';
  static const String _password = 'admin123';
  static const String _prefKey = 'auth_is_authenticated';

  final ValueNotifier<bool> isAuthenticatedNotifier = ValueNotifier(false);

  final ValueNotifier<bool> isGuestNotifier = ValueNotifier(false);
  bool get _guest => isGuestNotifier.value;
  set _guest(bool value) => isGuestNotifier.value = value;
  bool get hasAppSession => isAuthenticated || _guest;

  bool get isAuthenticated => isAuthenticatedNotifier.value;

  /// E-mail of the (single, hardcoded) account.
  String get email => _email;

  /// Restores session from SharedPreferences. Call once at app startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefKey) ?? false;
    if (kIsWeb) {
      try {
        final session = await BrowserBridge.call('auth.session');
        _guest = session == 'guest';
        isAuthenticatedNotifier.value = session == 'admin';
        await prefs.setBool(_prefKey, isAuthenticatedNotifier.value);
        await prefs.setBool('auth_is_guest', _guest);
      } catch (_) {
        // Offline access to previously stored data; API still validates cookies.
        _guest = prefs.getBool('auth_is_guest') ?? false;
        isAuthenticatedNotifier.value = saved;
      }
    } else {
      isAuthenticatedNotifier.value = saved;
    }
  }

  /// Returns true if credentials match; false otherwise.
  Future<bool> login(String email, String password) async {
    final accepted = kIsWeb
        ? await BrowserBridge.call('auth.login', {'email': email.trim(), 'password': password}) == true
        : email.trim() == _email && password == _password;
    if (accepted) {
      _guest = false;
      isAuthenticatedNotifier.value = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      if (kIsWeb) await prefs.setBool('auth_is_guest', false);
      return true;
    }
    return false;
  }

  Future<void> enterAsGuest() async {
    if (!kIsWeb) { await logout(); return; }
    await BrowserBridge.call('auth.guest');
    _guest = true;
    isAuthenticatedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_is_guest', true);
    await prefs.setBool(_prefKey, false);
  }

  Future<void> logout() async {
    if (kIsWeb) await BrowserBridge.call('auth.logout');
    _guest = false;
    isAuthenticatedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
    await prefs.setBool('auth_is_guest', false);
  }
}
