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

  bool get isAuthenticated => isAuthenticatedNotifier.value;

  /// Restores session from SharedPreferences. Call once at app startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefKey) ?? false;
    isAuthenticatedNotifier.value = saved;
  }

  /// Returns true if credentials match; false otherwise.
  Future<bool> login(String email, String password) async {
    if (email.trim() == _email && password == _password) {
      isAuthenticatedNotifier.value = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    isAuthenticatedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, false);
  }
}
