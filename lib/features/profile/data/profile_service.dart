import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/account_api.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/logger/app_logger.dart';
import '../domain/user_profile.dart';

/// Profile as stored on this device.
class ProfileRecord {
  final UserProfile profile;

  /// Last version known to be on the server, used to merge offline edits.
  final UserProfile base;
  final int revision;
  final bool dirty;

  const ProfileRecord({
    this.profile = UserProfile.empty,
    this.base = UserProfile.empty,
    this.revision = 0,
    this.dirty = false,
  });

  factory ProfileRecord.fromJson(Map<String, dynamic> json) => ProfileRecord(
        profile: UserProfile.fromJson(json['profile'] as Map<String, dynamic>),
        base: UserProfile.fromJson(json['base'] as Map<String, dynamic>),
        revision: json['revision'] as int,
        dirty: json['dirty'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'profile': profile.toJson(),
        'base': base.toJson(),
        'revision': revision,
        'dirty': dirty,
      };
}

/// Local-first profile, identical in the APK and the PWA.
///
/// Reading and saving never need the network. Without an account the profile
/// stays only on this device; with one it is synchronized when online. Records
/// are kept per owner, so accounts sharing a device never mix.
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();
  factory ProfileService() => _instance;
  ProfileService._internal();

  static const _prefix = 'profile_record_';
  static const _guest = 'guest';
  static const _admin = 'admin';

  final AuthService _auth = AuthService();
  final ValueNotifier<ProfileRecord> record =
      ValueNotifier(const ProfileRecord());

  SharedPreferences? _prefs;
  String? _lastOwner;
  Future<bool>? _syncing;

  String get _owner =>
      _auth.account?.id ?? (_auth.isAuthenticated ? _admin : _guest);

  /// Call after [AuthService.init].
  Future<void> init() async {
    if (_prefs != null) return;
    final prefs = _prefs = await SharedPreferences.getInstance();
    _lastOwner = _owner;
    // Copies of accounts no longer signed in here (all of it is on the server).
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await _discardIfSynced(key.substring(_prefix.length));
    }
    _auth.accountNotifier.addListener(_ownerChanged);
    _auth.isAuthenticatedNotifier.addListener(_ownerChanged);
    _publish();
  }

  void _ownerChanged() {
    final previous = _lastOwner;
    if (previous == _owner) return;
    _lastOwner = _owner;
    _publish();
    if (previous != null) _discardIfSynced(previous);
    sync();
  }

  Future<void> _discardIfSynced(String owner) async {
    if (owner == _owner || owner == _guest || owner == _admin) return;
    // Unsent edits wait for that account's next login.
    if (!_read(owner).dirty) await _prefs?.remove('$_prefix$owner');
  }

  ProfileRecord _read(String owner) {
    final raw = _prefs?.getString('$_prefix$owner');
    if (raw == null) return const ProfileRecord();
    try {
      return ProfileRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error) {
      AppLogger.warning('ProfileService: unreadable record: $error');
      return const ProfileRecord();
    }
  }

  Future<void> _write(String owner, ProfileRecord value) async {
    final stored =
        await _prefs!.setString('$_prefix$owner', jsonEncode(value.toJson()));
    if (!stored) throw StateError('Não foi possível salvar neste aparelho.');
    if (owner == _owner) _publish();
  }

  void _publish() => record.value = _read(_owner);

  /// Saves on the device (works offline) and syncs in the background.
  /// Throws only when the device itself cannot store it.
  Future<void> save(UserProfile profile) async {
    await init();
    final current = _read(_owner);
    if (profile == current.profile) return;
    await _write(
      _owner,
      ProfileRecord(
        profile: profile,
        base: current.base,
        revision: current.revision,
        dirty: _auth.account != null,
      ),
    );
    sync();
  }

  /// Deletes the account on the server and its copy on this device.
  Future<void> deleteAccount(String password) async {
    final id = _auth.account?.id;
    if (id == null) return;
    await _auth.deleteAccount(password);
    await _prefs?.remove('$_prefix$id');
  }

  /// Sends pending edits and brings changes made on other devices. Never
  /// throws; returns true when the device and the server match.
  Future<bool> sync() {
    if (_prefs == null || _auth.account == null) return Future.value(false);
    final running = _syncing;
    // Edits made meanwhile are picked up by the running sync.
    if (running != null) return running;
    final future = _sync();
    _syncing = future;
    return future.whenComplete(() {
      _syncing = null;
    });
  }

  Future<bool> _sync() async {
    while (true) {
      final account = _auth.account;
      if (account == null) return false;
      final token = _auth.accountToken;
      var done = false;
      try {
        done = await _syncAccount(account.id, token);
      } on AccountException catch (error) {
        AppLogger.warning('ProfileService: sync refused: ${error.status}');
        if (error.status == 401) await _auth.expireAccount(account.id, token);
      } catch (error) {
        AppLogger.debug('ProfileService: offline, sync later: $error');
      }
      final current = _auth.account?.id;
      if (current == null) return false;
      // Another account signed in, or an edit arrived at the very end.
      final again = current != account.id || (done && _read(current).dirty);
      if (!again) return done;
    }
  }

  Future<bool> _syncAccount(String id, String? token) async {
    var remote = await AccountApi.getProfile(token);
    for (var attempt = 0; attempt < 5; attempt++) {
      if (_auth.account?.id != id) return false;
      await _adoptGuestProfile(id, remote);
      if (_auth.account?.id != id) return false;

      final local = _read(id);
      final theirs = UserProfile.fromJson(remote.profile);
      final merged = local.dirty
          ? UserProfile.merge(base: local.base, mine: local.profile, theirs: theirs)
          : theirs;
      if (merged == theirs) {
        await _write(id, ProfileRecord(
          profile: theirs, base: theirs, revision: remote.revision,
        ));
        return true;
      }

      final result =
          await AccountApi.putProfile(token, merged.toJson(), remote.revision);
      if (!result.conflict) {
        final sent = UserProfile.fromJson(result.profile);
        // The account may have been deleted during the request...
        if (!_prefs!.containsKey('$_prefix$id')) return false;
        // ...or the user may have edited the profile or signed out.
        final edited = UserProfile.merge(
          base: local.profile, mine: _read(id).profile, theirs: sent,
        );
        if (_auth.account?.id != id && edited == sent) {
          await _prefs!.remove('$_prefix$id');
          return true;
        }
        await _write(id, ProfileRecord(
          profile: edited,
          base: sent,
          revision: result.revision,
          dirty: edited != sent,
        ));
        if (edited == sent) return true;
      }
      remote = result;
    }
    return false;
  }

  /// First login of an account that never had a profile: what the person
  /// filled in before having an account moves into it.
  Future<void> _adoptGuestProfile(String id, RemoteProfile remote) async {
    if (remote.revision != 0) return;
    final local = _read(id);
    final guest = _read(_guest).profile;
    if (local.dirty || guest.isEmpty) return;
    await _write(id, ProfileRecord(profile: guest, dirty: true));
    await _prefs!.remove('$_prefix$_guest');
  }
}
