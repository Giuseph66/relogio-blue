import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../platform/browser_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_api.dart';

/// Session of the app. Three independent kinds:
///  * administrator — [isAuthenticated]; unlocks the admin-only sections;
///  * participant account — [account]; optional, links the profile between
///    the APK and the PWA and never grants admin access;
///  * guest — no account.
///
/// Sessions are remembered, so the app opens offline after a first login.
class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Opens the native admin screens offline. Server-side privileges depend only
  // on the session token issued by the server.
  static const String _email = 'admin@gmail.com';
  // Salted SHA-256: the password is 20 random characters (~99 bits), so it
  // cannot be guessed from what is inside the APK.
  static const String _passwordSalt = '1e4eae586d0346b4106d41b7db34c664';
  static const String _passwordHash =
      '06d533eba9f66f148d1577637d06761c0928449926e53d0553ce07352c146234';
  static const String _prefKey = 'auth_is_authenticated';
  static const String _adminVersionKey = 'auth_admin_version';
  static const String _adminTokenKey = 'auth_admin_token';
  static const String _accountIdKey = 'auth_account_id';
  static const String _accountEmailKey = 'auth_account_email';
  static const String _accountTokenKey = 'auth_account_token';

  final ValueNotifier<bool> isAuthenticatedNotifier = ValueNotifier(false);
  final ValueNotifier<bool> isGuestNotifier = ValueNotifier(false);
  final ValueNotifier<AppAccount?> accountNotifier = ValueNotifier(null);

  /// The server ended the account session (expired or revoked).
  bool sessionExpired = false;

  String? _token;

  bool get _guest => isGuestNotifier.value;
  set _guest(bool value) => isGuestNotifier.value = value;

  AppAccount? get account => accountNotifier.value;

  /// Account token (native only; the browser uses an HttpOnly cookie).
  String? get accountToken => _token;

  bool get hasAppSession => isAuthenticated || _guest || account != null;

  bool get isAuthenticated => isAuthenticatedNotifier.value;

  /// E-mail of the administrator account.
  String get email => _email;

  @visibleForTesting
  static bool isLocalAdminPassword(String password) =>
      sha256.convert(utf8.encode('$_passwordSalt:${password.trim()}')).toString() ==
      _passwordHash;

  // Read from storage: background isolates have no session in memory.
  static Future<SharedPreferences> _freshPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  static Future<bool> isStoredAdmin() async =>
      (await _freshPrefs()).getBool(_prefKey) ?? false;

  /// Native administrator session. The browser uses its HttpOnly cookie.
  static Future<String?> storedAdminToken() async =>
      kIsWeb ? null : (await _freshPrefs()).getString(_adminTokenKey);

  /// Restores the saved session. Call once at app startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_prefKey) ?? false;
    final accountId = prefs.getString(_accountIdKey);
    final savedAccount = accountId == null
        ? null
        : AppAccount(id: accountId, email: prefs.getString(_accountEmailKey) ?? '');
    _token = prefs.getString(_accountTokenKey);

    if (!kIsWeb) {
      // Admin sessions opened with a previous built-in password end here.
      final valid = saved && prefs.getString(_adminVersionKey) == _passwordHash;
      if (saved && !valid) {
        await prefs.setBool(_prefKey, false);
        await prefs.remove(_adminTokenKey);
      }
      isAuthenticatedNotifier.value = valid;
      accountNotifier.value = savedAccount;
      return;
    }
    try {
      final current = await AccountApi.session();
      if (current != null) {
        await _setAccount(current, null);
        return;
      }
      final session = await BrowserBridge.call('auth.session');
      sessionExpired = savedAccount != null && session != 'admin';
      await _clearAccount();
      _guest = session == 'guest';
      isAuthenticatedNotifier.value = session == 'admin';
      await prefs.setBool(_prefKey, isAuthenticatedNotifier.value);
      await prefs.setBool('auth_is_guest', _guest);
    } catch (_) {
      // Offline access to previously stored data; API still validates cookies.
      _guest = prefs.getBool('auth_is_guest') ?? false;
      isAuthenticatedNotifier.value = saved;
      accountNotifier.value = savedAccount;
    }
  }

  /// Signs in as administrator or participant. Returns false on wrong
  /// credentials; throws [AccountException] for other refusals and the network
  /// error when the server cannot be reached.
  Future<bool> login(String email, String password) async {
    final bool admin;
    String? adminToken;
    if (kIsWeb) {
      admin = await BrowserBridge.call('auth.login', {'email': email.trim(), 'password': password}) == true;
    } else {
      final local = email.trim() == _email && isLocalAdminPassword(password);
      try {
        adminToken = await AccountApi.adminLogin(email.trim(), password);
      } catch (_) {
        if (!local) rethrow;
      }
      admin = local || adminToken != null;
    }
    if (admin) {
      await _leaveAccount();
      _guest = false;
      isAuthenticatedNotifier.value = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, true);
      await prefs.setString(_adminVersionKey, _passwordHash);
      if (adminToken != null) await prefs.setString(_adminTokenKey, adminToken);
      if (kIsWeb) await prefs.setBool('auth_is_guest', false);
      return true;
    }
    try {
      await _authenticate(email, password, register: false);
      return true;
    } on AccountException catch (error) {
      if (error.status == 401) return false;
      rethrow;
    }
  }

  /// Creates a participant account and signs in.
  Future<void> register(String email, String password) =>
      _authenticate(email, password, register: true);

  Future<void> _authenticate(String email, String password,
      {required bool register}) async {
    final (account, token) = await AccountApi.authenticate(
      email.trim(),
      password,
      register: register,
    );
    await _setAccount(account, token);
  }

  Future<void> _setAccount(AppAccount account, String? token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountIdKey, account.id);
    await prefs.setString(_accountEmailKey, account.email);
    if (token != null) await prefs.setString(_accountTokenKey, token);
    await prefs.remove(_adminTokenKey);
    await prefs.setBool(_prefKey, false);
    await prefs.setBool('auth_is_guest', false);
    _token = token;
    sessionExpired = false;
    _guest = false;
    isAuthenticatedNotifier.value = false;
    accountNotifier.value = account;
  }

  Future<void> _clearAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accountIdKey);
    await prefs.remove(_accountEmailKey);
    await prefs.remove(_accountTokenKey);
    _token = null;
    accountNotifier.value = null;
  }

  /// Ends the account session on the server and forgets it here.
  Future<void> _leaveAccount() async {
    if (account == null) return;
    try {
      await AccountApi.logout(_token);
    } catch (_) {
      // The browser cannot drop an HttpOnly cookie by itself. Natively,
      // discarding the token is enough to sign out while offline.
      if (kIsWeb) rethrow;
    }
    await _clearAccount();
  }

  /// The server refused the session used with [token] for [accountId].
  Future<void> expireAccount(String accountId, String? token) async {
    if (account?.id != accountId || _token != token) return;
    sessionExpired = true;
    await _clearAccount();
  }

  /// Permanently deletes the participant account and its profile.
  Future<void> deleteAccount(String password) async {
    await AccountApi.delete(_token, password);
    if (kIsWeb) {
      try {
        await BrowserBridge.call('push.disable');
      } catch (_) {
        // The browser subscription is dropped even when the API refuses.
      }
    }
    await _clearAccount();
  }

  Future<void> enterAsGuest() async {
    if (!kIsWeb) { await logout(); return; }
    await _leaveAccount();
    await BrowserBridge.call('auth.guest');
    _guest = true;
    isAuthenticatedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auth_is_guest', true);
    await prefs.setBool(_prefKey, false);
  }

  Future<void> logout() async {
    // First, so the push subscription is removed while still authorized.
    if (kIsWeb) await BrowserBridge.call('auth.logout');
    await _leaveAccount();
    sessionExpired = false;
    _guest = false;
    isAuthenticatedNotifier.value = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_adminTokenKey);
    await prefs.setBool(_prefKey, false);
    await prefs.setBool('auth_is_guest', false);
  }
}
